#!/bin/bash
#SBATCH --job-name=PetaKit5D_Compute
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=240G
#SBATCH --time=48:00:00
#SBATCH --output=logs/compute_job_%j.log
#SBATCH --error=logs/compute_job_%j.err

# --- Environment Configuration ---
# These can be overridden via sbatch --export=VAR=VAL
HPC_HOME="${HPC_HOME:-$HOME}"
ENV_NAME="${ENV_NAME:-ppk5d}"
PYTHON_BIN="${HPC_HOME}/${ENV_NAME}/bin/python"

set -e # Exit immediately if any command fails

echo "Job $SLURM_JOB_ID started on compute node $(hostname) at $(date)"
echo "Using $SLURM_CPUS_PER_TASK CPUs on node $SLURM_NODELIST"

# Remote script paths
REMOTE_CONFIG_SCRIPT="${HPC_HOME}/generate_config.py"
REMOTE_JOB_SCRIPT="${HPC_HOME}/process_job.py"
CONFIG_FILE="${HPC_HOME}/pypetakit_config.json"

# Ensure logs directory exists
mkdir -p "${HPC_HOME}/logs"

echo "--- (1/2) Running Python config generator ---"
# We generate the config locally on the node to ensure paths are correct
$PYTHON_BIN "$REMOTE_CONFIG_SCRIPT" --output "$CONFIG_FILE"

echo "--- (2/2) Running Python job script ---"
# Expecting DATASET_PATH to be passed via --export
if [ -z "$DATASET_PATH" ]; then
    echo "❌ ERROR: DATASET_PATH is not defined."
    echo "   Please submit with: sbatch --export=ALL,DATASET_PATH=/path/to/data submit_compute_job.sbatch"
    exit 1
fi

$PYTHON_BIN "$REMOTE_JOB_SCRIPT" --dataset "$DATASET_PATH" --config-file "$CONFIG_FILE"

echo "✅ Job $SLURM_JOB_ID finished successfully at $(date)"
