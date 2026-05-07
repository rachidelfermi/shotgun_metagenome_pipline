# 📘 Metagenome Pipeline: From FASTQ to MAGs

## Overview

This pipeline performs a complete metagenomic analysis starting from raw paired-end FASTQ files and producing:

- Quality-controlled reads  
- Taxonomic and functional profiles (read-based)  
- Metagenome assemblies  
- Contig coverage profiles  
- Metagenome-Assembled Genomes (MAGs)  
- Taxonomic and quality annotation of MAGs  

The workflow is optimized for:

- Environmental microbiomes (soil, rhizosphere, plant-associated)  
- HPC environments (SLURM)  
- Large-scale datasets (storage-efficient, `.fastq.gz`-based)  

---

## 🧱 Pipeline Structure

```
RAW FASTQ (.fastq.gz)
        │
        ▼
[1] Preprocessing (fastp, optional bbduk)
        │
        ▼
Clean reads (.fastq.gz)
        │
        ├──────────────► [2] Read-based profiling
        │                    (Kaiju, Kraken2, Bracken, MetaPhlAn, HUMAnN3)
        │
        ▼
[3] Assembly (MEGAHIT)
        │
        ▼
Contigs (contigs.fa)
        │
        ▼
[4] Mapping (Bowtie2)
        │
        ▼
BAM files
        │
        ▼
[5] Coverage calculation (JGI / CoverM)
        │
        ▼
[6] Binning (MetaBAT2, MaxBin2, SemiBin2)
        │
        ▼
[7] Refinement (DASTool + RefineM)
        │
        ▼
MAGs
        │
        ▼
[8] Evaluation & Annotation
     (CheckM2, GTDB-Tk, CoverM)
```

---

## 📁 Directory Organization

```
project/
└── sulaiman/
    ├── metaResults/
    │   ├── temp/
    │   │   └── hr/                  # Clean reads (.fastq.gz)
    │   └── result/
    │       ├── metadata.txt
    │       └── samples.txt
    │
    ├── array_runs/                 # Read-based analysis
    ├── array_runs_asm_2/           # Assembly outputs
    ├── array_runs_mapping/         # BAM files (per sample)
    └── array_runs_binning/         # MAGs and binning results
```

---

## ⚙️ Step-by-Step Description

### 1. Preprocessing

**Tools:**
- fastp (quality filtering, adapter trimming)  
- bbduk (optional contaminant/organelle removal)  

**Key features:**
- Works directly on `.fastq.gz` (no decompression)  
- Storage-efficient  

**Outputs:**
```
metaResults/temp/hr/sample_1.fastq.gz
metaResults/temp/hr/sample_2.fastq.gz
```

---

### 2. Read-Based Profiling

**Tools:**
- Kaiju (protein-level classification)  
- Kraken2 + Bracken (k-mer taxonomy)  
- MetaPhlAn (marker gene profiling)  
- HUMAnN3 (functional profiling)  

**Outputs:**
- Taxonomic profiles  
- Functional pathways and gene families  

---

### 3. Assembly

**Tool:**
- MEGAHIT  

**Output:**
```
array_runs_asm_2/sample/metaResults/result/assembly/contigs.fa
```

---

### 4. Mapping

**Tool:**
- Bowtie2 + Samtools  

**Purpose:**
- Map reads back to their own assembly (self-mapping)  

**Output:**
```
array_runs_mapping/sample/map/sample.bam
```

---

### 5. Coverage Calculation

**Tools:**
- jgi_summarize_bam_contig_depths  
- coverm  

**Output:**
- Contig depth tables used for binning  

---

### 6. Binning

**Tools:**
- MetaBAT2  
- MaxBin2  
- SemiBin2  

**Approach:**
- Single-sample binning using contig coverage  

---

### 7. Refinement

**Tools:**
- DASTool (consensus binning)  
- RefineM (contamination removal)  

**Output:**
```
refined_bins/*.fa
```

---

### 8. MAG Evaluation & Annotation

**Tools:**
- CheckM2 → completeness & contamination  
- GTDB-Tk → taxonomy  
- CoverM → abundance  

---

## 🚀 Running the Pipeline

Each step runs as a SLURM array job:

```bash
sbatch --array=1-N preprocess.sh
sbatch --array=1-N assembly.sh
sbatch --array=1-N mapping.sh
sbatch --array=1-N binning.sh
sbatch --array=1-N read_based.sh
```

Where `N = number of samples`

---
