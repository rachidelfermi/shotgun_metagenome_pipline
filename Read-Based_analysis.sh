#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --time=36:00:00
#SBATCH --partition=compute
#SBATCH --job-name=RB_array
#SBATCH --output=logs/%x-%A_%a.log
#SBATCH --array=1-XXX

set -euo pipefail

echo "========================================================"
echo "        READ-BASED PIPELINE (CLEAN, NO SCRATCH)"
echo "========================================================"

###############################################################################
# CONDA
###############################################################################
eval "$(/srv/data/rachid.elfermi/miniconda3/bin/conda shell.bash hook)"

###############################################################################
# PATHS
###############################################################################
PARENTDIR=$(dirname "$(pwd)")
OUTDIR="$PARENTDIR/sulaiman"
ARRAY_RUNS="$OUTDIR/array_runs"

RAW_FASTQ_DIR="$OUTDIR/metaResults/temp/hr"
MASTER_METADATA="$OUTDIR/metaResults/result/metadata.txt"
SAMPLES_LIST="$OUTDIR/metaResults/result/samples.txt"

DB_BASE="/home/rachid.elfermi/lustre/omics_pacb-sd3mvfopfps/users/rachid.elfermi/EasyMetagenome-master/db"

###############################################################################
# PARAMETERS
###############################################################################
TPS=40
READLEN=150
KRAKEN_CONF=0.1

KAIJU_ENABLE=1
KRAKEN_ENABLE=1
METAPHLAN_ENABLE=1
HUMANN_ENABLE=1

KAIJU_DB="$DB_BASE/kaiju/refseq_nr"
KRAKEN_DB="$DB_BASE/kraken2/pluspf"

MPA_DB="$DB_BASE/metaphlan4"
MPA_IDX="mpa_vJun23_CHOCOPhlAnSGB_202403"

###############################################################################
# SAMPLE
###############################################################################
[[ -s "$SAMPLES_LIST" ]] || tail -n+2 "$MASTER_METADATA" | cut -f1 > "$SAMPLES_LIST"
SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLES_LIST")

echo "[INFO] Sample: $SAMPLE"

R1="$RAW_FASTQ_DIR/${SAMPLE}_1.fastq"
R2="$RAW_FASTQ_DIR/${SAMPLE}_2.fastq"

###############################################################################
# DIRECTORIES
###############################################################################
RUN_DIR="$ARRAY_RUNS/$SAMPLE"
TEMP_DIR="$RUN_DIR/metaResults/temp"
RESULT_DIR="$RUN_DIR/metaResults/result"

mkdir -p "$TEMP_DIR" "$RESULT_DIR"/{kaiju,kraken2,bracken,metaphlan,humann3}

###############################################################################
# 1) CONCAT (LOCAL)
###############################################################################
CONCAT="$TEMP_DIR/${SAMPLE}.fq"

if [[ ! -f "$CONCAT" ]]; then
    echo "[concat]"
    cat "$R1" "$R2" > "$CONCAT"
fi

###############################################################################
# 2) KAIJU
###############################################################################
if [[ "$KAIJU_ENABLE" == 1 && ! -f "$RESULT_DIR/kaiju/${SAMPLE}.species.tsv" ]]; then
    echo "[Kaiju]"
    conda activate kaiju

    FMI=$(ls "$KAIJU_DB"/kaiju_db_*.fmi | head -n1)

    kaiju \
        -t "$KAIJU_DB/nodes.dmp" \
        -f "$FMI" \
        -i "$R1" -j "$R2" \
        -o "$TEMP_DIR/${SAMPLE}.kaiju.out" \
        -z "$TPS"

    kaiju2table \
        -t "$KAIJU_DB/nodes.dmp" \
        -n "$KAIJU_DB/names.dmp" \
        -r species \
        -o "$RESULT_DIR/kaiju/${SAMPLE}.species.tsv" \
        "$TEMP_DIR/${SAMPLE}.kaiju.out"
fi

###############################################################################
# 3) KRAKEN2 + BRACKEN
###############################################################################
if [[ "$KRAKEN_ENABLE" == 1 && ! -f "$RESULT_DIR/kraken2/${SAMPLE}.report" ]]; then
    echo "[Kraken2]"
    conda activate kraken2.1.3

    kraken2 \
        --db "$KRAKEN_DB" \
        --paired "$R1" "$R2" \
        --threads "$TPS" \
        --confidence "$KRAKEN_CONF" \
        --report "$RESULT_DIR/kraken2/${SAMPLE}.report" \
        --output "$TEMP_DIR/${SAMPLE}.kraken"

    echo "[Bracken]"
    for lvl in P F G S; do
        bracken \
            -d "$KRAKEN_DB" \
            -i "$RESULT_DIR/kraken2/${SAMPLE}.report" \
            -r "$READLEN" \
            -l "$lvl" \
            -t "$TPS" \
            -o "$RESULT_DIR/bracken/${SAMPLE}.${lvl}.brk"
    done
fi

###############################################################################
# 4) METAPHLAN
###############################################################################
if [[ "$METAPHLAN_ENABLE" == 1 && ! -f "$RESULT_DIR/metaphlan/${SAMPLE}_bugs.tsv" ]]; then
    echo "[MetaPhlAn]"
    conda activate humann3

    metaphlan "$CONCAT" \
        --input_type fastq \
        --nproc "$TPS" \
        --bowtie2db "$MPA_DB" \
        -x "$MPA_IDX" \
        -o "$RESULT_DIR/metaphlan/${SAMPLE}_bugs.tsv"
fi

TAX_PROFILE="$RESULT_DIR/metaphlan/${SAMPLE}_bugs.tsv"

###############################################################################
# 5) HUMANN3 (LOCAL TMP ONLY)
###############################################################################
if [[ "$HUMANN_ENABLE" == 1 && ! -f "$RESULT_DIR/humann3/${SAMPLE}_genefamilies.tsv" ]]; then
    echo "[HUMAnN3]"
    conda activate humann3

    HUMANN_TMP="$TEMP_DIR/humann_tmp"
    rm -rf "$HUMANN_TMP"
    mkdir -p "$HUMANN_TMP"

    export TMPDIR="$HUMANN_TMP"

    humann \
        --input "$CONCAT" \
        --threads "$TPS" \
        --taxonomic-profile "$TAX_PROFILE" \
        --output "$HUMANN_TMP" \
        --output-basename "$SAMPLE"

    cp "$HUMANN_TMP"/*.tsv "$RESULT_DIR/humann3/"
    rm -rf "$HUMANN_TMP"
fi

###############################################################################
echo "========================================================"
echo " DONE → $SAMPLE"
echo "========================================================"