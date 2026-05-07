#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --time=36:00:00
#SBATCH --partition=compute
#SBATCH --job-name=BIN_ARRAY
#SBATCH --output=logs/%x-%A_%a.log
#SBATCH --array=1-XXX

set -euo pipefail
export PS1="${PS1-}"

echo "================================================================"
echo "                EASY METAGENOME – BINNING (CLEAN)"
echo "================================================================"
echo "[START] $(date)"
echo "[JOB]   ${SLURM_JOB_ID:-manual}"
echo "[NODE]  $(hostname)"
echo "----------------------------------------------------------------"

###############################################################################
# CONDA
###############################################################################
eval "$(/srv/data/rachid.elfermi/miniconda3/bin/conda shell.bash hook)"

###############################################################################
# PATHS
###############################################################################
PARENTDIR=$(dirname "$(pwd)")
OUTDIR="$PARENTDIR/sulaiman"

ASM_BASE="$OUTDIR/array_runs_asm_2"
MAP_BASE="$OUTDIR/array_runs_mapping"

MASTER_META="$OUTDIR/metaResults/result/metadata.txt"
SAMPLE_LIST="$OUTDIR/metaResults/result/samples.txt"

DB_BASE="/srv/lustre01/project/omics_pacb-sd3mvfopfps/users/rachid.elfermi/EasyMetagenome-master/db"

###############################################################################
# SAMPLE
###############################################################################
[[ -s "$SAMPLE_LIST" ]] || tail -n+2 "$MASTER_META" | cut -f1 > "$SAMPLE_LIST"
SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLE_LIST")

echo "[INFO] Sample: $SAMPLE"

###############################################################################
# DIRECTORIES
###############################################################################
RUN_DIR="$OUTDIR/array_runs_binning/$SAMPLE"
RESULT_DIR="$RUN_DIR/metaResults/result"

mkdir -p "$RESULT_DIR"/{depth,metabat2,maxbin2,semibin2,refined_bins,checkm2,gtdb,coverm_bins,das_tool}

###############################################################################
# INPUT FILES
###############################################################################
CONTIGS="$ASM_BASE/$SAMPLE/metaResults/result/assembly/contigs.fa"
MAP_DIR="$MAP_BASE/$SAMPLE/map"
BAM="$MAP_DIR/${SAMPLE}.bam"

if [[ ! -f "$CONTIGS" ]]; then
    echo "[ERROR] Missing contigs for $SAMPLE"
    exit 1
fi

if [[ ! -f "$BAM" ]]; then
    echo "[ERROR] Missing BAM for $SAMPLE"
    exit 2
fi

###############################################################################
# 1) DEPTH
###############################################################################
DEPTH_TSV="$RESULT_DIR/depth/depth.tsv"

if [[ ! -s "$DEPTH_TSV" ]]; then
    echo "[DEPTH]"
    conda activate binning

    jgi_summarize_bam_contig_depths \
        --minContigLength 2000 \
        --percentIdentity 97 \
        --outputDepth "$DEPTH_TSV" \
        "$BAM"
fi

###############################################################################
# 2) METABAT2
###############################################################################
if [[ ! -f "$RESULT_DIR/metabat2/bin.1.fa" ]]; then
    echo "[MetaBAT2]"
    conda activate binning

    metabat2 \
        -i "$CONTIGS" \
        -a "$DEPTH_TSV" \
        -o "$RESULT_DIR/metabat2/bin" \
        -t 50
fi

###############################################################################
# 3) MAXBIN2
###############################################################################
if [[ ! -f "$RESULT_DIR/maxbin2/bin.001.fasta" ]]; then
    echo "[MaxBin2]"
    conda activate binning

    run_MaxBin.pl \
        -contig "$CONTIGS" \
        -abund "$DEPTH_TSV" \
        -thread 50 \
        -out "$RESULT_DIR/maxbin2/bin"
fi

###############################################################################
# 4) SEMIBIN2
###############################################################################
if ! compgen -G "$RESULT_DIR/semibin2/*.fa" > /dev/null; then
    echo "[SemiBin2]"
    conda activate binning

    SemiBin2 \
        single_easy_bin \
        --input-fasta "$CONTIGS" \
        -b "$BAM" \
        --self-supervised \
        -p 50 \
        --output "$RESULT_DIR/semibin2"
fi

###############################################################################
# 5) DASTOOL
###############################################################################
REFINED_DIR="$RESULT_DIR/refined_bins"
DASTOOL_DIR="$RESULT_DIR/das_tool"

if ! compgen -G "$REFINED_DIR/*.fa" > /dev/null; then
    echo "[DASTool]"
    conda activate binning

    mkdir -p "$DASTOOL_DIR"

    # MetaBAT2 TSV
    > "$DASTOOL_DIR/metabat2.tsv"
    for f in "$RESULT_DIR"/metabat2/*.fa; do
        [[ -e "$f" ]] || continue
        b=$(basename "$f" .fa)
        awk -v bin="$b" '/^>/ {print substr($1,2) "\t" bin}' "$f" >> "$DASTOOL_DIR/metabat2.tsv"
    done

    # MaxBin2 TSV
    > "$DASTOOL_DIR/maxbin2.tsv"
    for f in "$RESULT_DIR"/maxbin2/*.fasta; do
        [[ -e "$f" ]] || continue
        b=$(basename "$f" .fasta)
        awk -v bin="$b" '/^>/ {print substr($1,2) "\t" bin}' "$f" >> "$DASTOOL_DIR/maxbin2.tsv"
    done

    # SemiBin2 TSV
    > "$DASTOOL_DIR/semibin2.tsv"
    for f in "$RESULT_DIR"/semibin2/*.fa; do
        [[ -e "$f" ]] || continue
        b=$(basename "$f" .fa)
        awk -v bin="$b" '/^>/ {print substr($1,2) "\t" bin}' "$f" >> "$DASTOOL_DIR/semibin2.tsv"
    done

    DAS_Tool \
        -i "$DASTOOL_DIR/metabat2.tsv","$DASTOOL_DIR/maxbin2.tsv","$DASTOOL_DIR/semibin2.tsv" \
        -c "$CONTIGS" \
        -l metabat2,maxbin2,semibin2 \
        -o "$DASTOOL_DIR/refine" \
        --threads 50 \
        --write_bins

    mkdir -p "$REFINED_DIR"
    cp "$DASTOOL_DIR"/refine_DASTool_bins/*.fa "$REFINED_DIR/"
fi

###############################################################################
# 6) CHECKM2
###############################################################################
if [[ ! -f "$RESULT_DIR/checkm2/quality_report.tsv" ]]; then
    echo "[CheckM2]"
    conda activate checkm2

    checkm2 predict \
        --threads 40 \
        --input "$REFINED_DIR" \
        --output-directory "$RESULT_DIR/checkm2" \
        -x fa
fi

###############################################################################
# 7) GTDB-TK
###############################################################################
if ! compgen -G "$RESULT_DIR/gtdb/*.summary.tsv" > /dev/null; then
    echo "[GTDB-Tk]"
    conda activate gtdbtk

    export GTDBTK_DATA_PATH="${DB_BASE}/gtdb2.4/release226"

    gtdbtk classify_wf \
        --genome_dir "$REFINED_DIR" \
        --out_dir "$RESULT_DIR/gtdb" \
        --cpus 40 \
        --skip_ani_screen \
        -x fa
fi

###############################################################################
# 8) COVERM (bins)
###############################################################################
COVERM_OUT="$RESULT_DIR/coverm_bins/${SAMPLE}_coverage.tsv"

if [[ ! -s "$COVERM_OUT" ]]; then
    echo "[CoverM]"
    conda activate coverm

    coverm genome \
        --bam-files "$BAM" \
        --genome-fasta-directory "$REFINED_DIR" \
        --genome-fasta-extension fa \
        --methods relative_abundance \
        --threads 40 \
        > "$COVERM_OUT"
fi

###############################################################################
echo "================================================================"
echo " DONE BINNING → $SAMPLE"
echo "================================================================"
echo "[END] $(date)"