#!/bin/bash
#SBATCH --job-name=HLA_HD_CRAM
#SBATCH --partition=compute
#SBATCH --cpus-per-task=10
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=hlahd_%j.out
#SBATCH --error=hlahd_%j.err

set -euo pipefail #stops running if any errors occur

# ============================================================================== #
# USER CONFIGURATION (Edit paths in this section)
# ============================================================================== #

#1) Base Installation Directory (where HLA-HD is installed)
BASE_DIR="${SLURM_SUBMIT_DIR:-$PWD}"

#2) Input CRAM File Configuration
CRAM_DIR="/path/to/your/cram_directory"
SAMPLE_ID="YOUR_SAMPLE_ID"

#3) Reference Genome
REF_FASTA="/path/to/your/reference/GRCh38.fasta"

#4) Working + Output Directories
TMP_DIR="${BASE_DIR}/tmp/${SAMPLE_ID}"
OUT_DIR="${BASE_DIR}/output/${SAMPLE_ID}"

# ============================================================================== #
# ENVIRONMENT & PATH SETUP
# ============================================================================== #

cd "$BASE_DIR"
export PATH="${BASE_DIR}/bin:${PATH}"

#Check dependencies are present (I've provided a yaml file of what has worked for me. 'conda env create -f environment.yml' followed by 'conda activate hlahd')
REQUIRED_TOOLS=("samtools" "bowtie2" "perl" "hla_est" "pick_up_allele")
echo "--> Verifying execution environment..."
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: Required tool '$tool' not found in PATH." >&2
        echo "Please ensure Conda environment or modules are loaded." >&2
        exit 1
    fi
done

#File locations (.cram and .crai)
CRAM="${CRAM_DIR}/${SAMPLE_ID}.cram"
CRAI="${CRAM_DIR}/${SAMPLE_ID}.cram.crai"

R1="${TMP_DIR}/${SAMPLE_ID}.read1.fastq"
R2="${TMP_DIR}/${SAMPLE_ID}.read2.fastq"

#Reset working directories for sample
rm -rf "${OUT_DIR:?}/${SAMPLE_ID}" "${TMP_DIR}"
mkdir -p "$TMP_DIR" "$OUT_DIR"

echo "=========================================================="
echo " Starting HLA-HD Run for Sample: ${SAMPLE_ID}"
echo "=========================================================="

# ============================================================================== #
# 1: Extract MHC Region from CRAM + Convert to Paired FASTQs
# ============================================================================== #
START_EXTRACT=$(date +%s)

echo "--> Slicing MHC region (chr6:28477797-33448354) from CRAM..."
samtools view -b -T "$REF_FASTA" -X "$CRAM" "$CRAI" "chr6:28477797-33448354" > "${TMP_DIR}/${SAMPLE_ID}.mhc.bam"

echo "--> Name sorting extracted reads..."
samtools sort -n -@ ${SLURM_CPUS_PER_TASK:-10} "${TMP_DIR}/${SAMPLE_ID}.mhc.bam" -o "${TMP_DIR}/${SAMPLE_ID}.mhc.sorted.bam"

echo "--> Converting to paired FASTQs..."
samtools fastq -1 "$R1" -2 "$R2" -0 /dev/null -s /dev/null "${TMP_DIR}/${SAMPLE_ID}.mhc.sorted.bam"

#cleanup intermediate BAM files
rm -f "${TMP_DIR}/${SAMPLE_ID}.mhc.bam" "${TMP_DIR}/${SAMPLE_ID}.mhc.sorted.bam"

END_EXTRACT=$(date +%s)
TIME_EXTRACT=$((END_EXTRACT - START_EXTRACT))

#measure temporary FASTQ storage prior to deletion
TEMP_STORAGE_HUMAN=$(du -sh "${TMP_DIR}" 2>/dev/null | cut -f1)
TEMP_FILE_COUNT=$(find "${TMP_DIR}" -type f | wc -l)

# ============================================================================== #
# 2: Run HLA-HD Allele Typing
# ============================================================================== #
START_HLA=$(date +%s)

#these are the parameters I use. I find a t of 10 speeds things up quite a bit, but feel free to change it for whatever suits your needs
echo "--> Running HLA-HD..."
hlahd.sh \
    -t 10 \
    -m 55 \
    -f freq_data/ \
    "$R1" \
    "$R2" \
    HLA_gene.split.txt \
    dictionary \  #for the dictionary we use the 3.15 ver of the IPD-IMGT/HLA Database. mentioned in the readme
    "$SAMPLE_ID" \
    "$OUT_DIR"

#do not run this commented chunk of code within this script. this is just how to generate an alternative dictionary.
#python3 bin/hlahd_update.py \
   # -g hla_gen.fasta \
   # -c hla_nuc.fasta \
   # -a align_dir/ \
   # -o dictionary315


END_HLA=$(date +%s)
TIME_HLA=$((END_HLA - START_HLA))

#Measure final output directory storage
PERM_STORAGE_HUMAN=$(du -sh "${OUT_DIR}" 2>/dev/null | cut -f1)
PERM_FILE_COUNT=$(find "${OUT_DIR}" -type f | wc -l)

#Clean up temporary FASTQ files after execution
rm -rf "$TMP_DIR"

# ============================================================================== #
# 3: Metrics/Stats of the Run
# ============================================================================== #
sleep 5 #Allow cgroups/sstat to sync peak memory stats

PEAK_RAM_KB=$(sstat -j ${SLURM_JOB_ID}.batch --format=MaxRSS -n 2>/dev/null | tr -d ' ' | head -n1)
if [[ -z "$PEAK_RAM_KB" || "$PEAK_RAM_KB" == "0" ]]; then
    if [ -f /sys/fs/cgroup/memory/job_${SLURM_JOB_ID}/memory.max_usage_in_bytes ]; then
        PEAK_BYTES=$(cat /sys/fs/cgroup/memory/job_${SLURM_JOB_ID}/memory.max_usage_in_bytes)
        PEAK_RAM_HUMAN="$(awk "BEGIN {printf \"%.2f GB\", ${PEAK_BYTES}/1073741824}")"
    else
        PEAK_RAM_HUMAN="N/A (Check sacct after completion)"
    fi
else
    PEAK_RAM_HUMAN="$(awk "BEGIN {printf \"%.2f GB\", ${PEAK_RAM_KB%K}/1048576}")"
fi

# ============================================================================== #
# 4: Print Output Metrics Report
# ============================================================================== #
echo ""
echo "=========================================================="
echo "               RUN PERFORMANCE REPORT                     "
echo "=========================================================="
echo "Sample ID:                      ${SAMPLE_ID}"
echo "Requested CPUs:                 ${SLURM_CPUS_PER_TASK:-10}"
echo "Requested Memory:               32G"
echo "----------------------------------------------------------"
echo "Time to extract MHC from CRAM:  $(printf '%02dh:%02dm:%02ds\n' $((TIME_EXTRACT/3600)) $((TIME_EXTRACT%3600/60)) $((TIME_EXTRACT%60)))"
echo "Time to run HLA-HD typing:      $(printf '%02dh:%02dm:%02ds\n' $((TIME_HLA/3600)) $((TIME_HLA%3600/60)) $((TIME_HLA%60)))"
echo "----------------------------------------------------------"
echo "Peak RAM Usage:                 ${PEAK_RAM_HUMAN}"
echo "----------------------------------------------------------"
echo "Disk Space Requirements:"
echo "  - Temp Storage (MHC FASTQs):   ${TEMP_STORAGE_HUMAN}"
echo "  - Permanent Storage (Output): ${PERM_STORAGE_HUMAN}"
echo "  - Number of Temp Files:       ${TEMP_FILE_COUNT}"
echo "  - Number of Permanent Files:  ${PERM_FILE_COUNT}"
echo "=========================================================="
echo " Run Complete for Sample: ${SAMPLE_ID}"
echo " Final results saved to: ${OUT_DIR}/${SAMPLE_ID}/result/"
echo "=========================================================="