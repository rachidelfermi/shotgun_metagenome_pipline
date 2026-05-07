#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --time=36:00:00
#SBATCH --partition=compute
#SBATCH --job-name=ASM_clean
#SBATCH --output=logs/%x-%A_%a.log
#SBATCH --array=1-XXX

set -euo pipefail

echo "========================================================"
echo "     MINIMAL ASSEMBLY → MAPPING → COVERAGE PIPELINE"
echo "========================================================"

eval "$(/srv/data/rachid.elfermi/miniconda3/bin/conda shell.bash hook)"

############################################################
# PATHS
############################################################
PARENTDIR=$(dirname "$(pwd)")
OUTDIR="$PARENTDIR/sulaiman"
ASM_RUNS="$OUTDIR/array_runs_asm"

RAW_FASTQ_DIR="$OUTDIR/metaResults/temp/hr"
MASTER_META="$OUTDIR/metaResults/result/metadata.txt"
SAMPLES_LIST="$OUTDIR/metaResults/result/samples.txt"

############################################################
# SAMPLE
############################################################
[[ -s "$SAMPLES_LIST" ]] || tail -n+2 "$MASTER_META" | cut -f1 > "$SAMPLES_LIST"
SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLES_LIST")

R1="$RAW_FASTQ_DIR/${SAMPLE}_1.fastq"
R2="$RAW_FASTQ_DIR/${SAMPLE}_2.fastq"

############################################################
# DIRS
############################################################
RUN_DIR="$ASM_RUNS/$SAMPLE"
RESULT_DIR="$RUN_DIR/metaResults/result"
TEMP_DIR="$RUN_DIR/metaResults/temp"

mkdir -p "$RESULT_DIR"/{assembly,map,coverm} "$TEMP_DIR"

ASSEMBLY="$RESULT_DIR/assembly/contigs.fa"

############################################################
# 1) ASSEMBLY (MEGAHIT)
############################################################
if [[ ! -f "$ASSEMBLY" ]]; then
    conda activate megahit

    megahit \
        -1 "$R1" -2 "$R2" \
        --presets meta-large \
        --min-contig-len 1000 \
        -t 40 \
        -o "$TEMP_DIR/megahit"

    mv "$TEMP_DIR/megahit/final.contigs.fa" "$ASSEMBLY"
fi

############################################################
# 2) MAPPING (SELF)
############################################################
if [[ ! -f "$RESULT_DIR/map/${SAMPLE}.bam" ]]; then
    conda activate binning

    bowtie2-build "$ASSEMBLY" "$TEMP_DIR/index"

    bowtie2 \
        -x "$TEMP_DIR/index" \
        -1 "$R1" -2 "$R2" \
        -p 40 \
        | samtools sort -o "$RESULT_DIR/map/${SAMPLE}.bam"

    samtools index "$RESULT_DIR/map/${SAMPLE}.bam"
fi

############################################################
# 3) COVERAGE
############################################################
if [[ ! -f "$RESULT_DIR/coverm/${SAMPLE}.tsv" ]]; then
    conda activate coverm

    coverm contig \
        --bam-files "$RESULT_DIR/map/${SAMPLE}.bam" \
        --methods mean covered_fraction length \
        --threads 40 \
        > "$RESULT_DIR/coverm/${SAMPLE}.tsv"
fi

############################################################
echo "========================================================"
echo " DONE → $SAMPLE"
echo "========================================================"