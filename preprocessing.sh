#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --time=24:00:00
#SBATCH --partition=compute
#SBATCH --job-name=MG_preproc_env
#SBATCH --output=logs/%x-%j.log

set -euo pipefail

echo "========================================================"
echo "   METAGENOME PREPROCESSING "
echo "========================================================"

###############################################################################
# CONDA
###############################################################################
eval "$(/srv/data/rachid.elfermi/miniconda3/bin/conda shell.bash hook)"
conda activate kneaddata

###############################################################################
# PATHS
###############################################################################
INPUTDIR="/srv/lustre01/project/omics_core-rqyo8fdrbpw/shared/souliman_zahreddine/metagenome/sulaimon"

PARENTDIR=$(dirname "$(pwd)")
OUTDIR="$PARENTDIR/sulaiman"
WD="$OUTDIR/metaResults"

TEMP_DIR="$WD/temp"
RESULT_DIR="$WD/result"

mkdir -p "$TEMP_DIR"/{qc,bbduk,hr} "$RESULT_DIR"

META="$RESULT_DIR/metadata.txt"
SAMPLES_LIST="$RESULT_DIR/samples.txt"

###############################################################################
# PARAMETERS
###############################################################################
CPUS="${SLURM_CPUS_PER_TASK:-40}"
RUN_BBDUK=F

DB="/home/rachid.elfermi/lustre/omics_core-rqyo8fdrbpw/users/rachid.elfermi/EasyMetagenome-master/db"

echo "[INFO] CPUs: $CPUS"
echo "[INFO] INPUT: $INPUTDIR"

###############################################################################
# 1) METADATA
###############################################################################
if [[ ! -s "$META" ]]; then
    echo "[metadata] Creating metadata.txt"
    echo -e "SampleID\tR1\tR2" > "$META"

    for R1 in "$INPUTDIR"/*_R1.fastq.gz; do
        base=$(basename "$R1")
        sid=$(echo "$base" | sed 's/_R1.fastq.gz//')
        R2="$INPUTDIR/${sid}_R2.fastq.gz"

        [[ -f "$R2" ]] || { echo "[WARN] Missing R2 for $sid"; continue; }

        echo -e "$sid\t${sid}_R1.fastq.gz\t${sid}_R2.fastq.gz" >> "$META"
    done
fi

###############################################################################
# 2) FASTP (DIRECT ON GZ)
###############################################################################
echo "[fastp]"

while read -r sid _; do
    [[ "$sid" == "SampleID" ]] && continue

    if [[ -f "$TEMP_DIR/qc/${sid}_1.fastq.gz" ]]; then
        echo "[fastp] Skip $sid"
        continue
    fi

    fastp \
        -i "$INPUTDIR/${sid}_R1.fastq.gz" \
        -I "$INPUTDIR/${sid}_R2.fastq.gz" \
        -o "$TEMP_DIR/qc/${sid}_1.fastq.gz" \
        -O "$TEMP_DIR/qc/${sid}_2.fastq.gz" \
        --thread "$CPUS" \
        --compression 6 \
        --detect_adapter_for_pe \
        --correction \
        --html "$TEMP_DIR/qc/${sid}.html" \
        --json "$TEMP_DIR/qc/${sid}.json" \
        > "$TEMP_DIR/qc/${sid}.log" 2>&1

done < "$META"

###############################################################################
# 3) BBDUK (OPTIONAL, GZ MODE)
###############################################################################
echo "[bbduk]"

while read -r sid _; do
    [[ "$sid" == "SampleID" ]] && continue

    if [[ "$RUN_BBDUK" == "T" ]]; then
        bbduk.sh \
            in1="$TEMP_DIR/qc/${sid}_1.fastq.gz" \
            in2="$TEMP_DIR/qc/${sid}_2.fastq.gz" \
            out1="$TEMP_DIR/bbduk/${sid}_1.fastq.gz" \
            out2="$TEMP_DIR/bbduk/${sid}_2.fastq.gz" \
            ref="$DB/organelle/organelle.fa.gz" \
            k=31 hdist=1 tpe tbo \
            threads="$CPUS"
    else
        cp "$TEMP_DIR/qc/${sid}_1.fastq.gz" "$TEMP_DIR/bbduk/${sid}_1.fastq.gz"
        cp "$TEMP_DIR/qc/${sid}_2.fastq.gz" "$TEMP_DIR/bbduk/${sid}_2.fastq.gz"
    fi

done < "$META"

###############################################################################
# 4) FINAL OUTPUT (GZ)
###############################################################################
echo "[final] Writing cleaned FASTQs (.gz)"

while read -r sid _; do
    [[ "$sid" == "SampleID" ]] && continue

    cp "$TEMP_DIR/bbduk/${sid}_1.fastq.gz" "$TEMP_DIR/hr/${sid}_1.fastq.gz"
    cp "$TEMP_DIR/bbduk/${sid}_2.fastq.gz" "$TEMP_DIR/hr/${sid}_2.fastq.gz"

done < "$META"

###############################################################################
# 5) SAMPLES LIST
###############################################################################
tail -n +2 "$META" | cut -f1 > "$SAMPLES_LIST"

echo "[samples] $(wc -l < "$SAMPLES_LIST") samples"

###############################################################################
# 6) CLEANUP
###############################################################################
echo "[cleanup] Removing intermediate files"

rm -rf "$TEMP_DIR/qc"
rm -rf "$TEMP_DIR/bbduk"

###############################################################################
echo "========================================================"
echo " PREPROCESSING COMPLETE (GZ MODE)"
echo "========================================================"
echo "OUTPUT: $TEMP_DIR/hr/*.fastq.gz"