#!/bin/bash
# run_workflow.sh
#
# A script to transfer PetaKit scripts to the HPC and submit the Slurm job.

# --- Configuration & Defaults ---
HPC_LOGIN="Discovery"
HPC_HOME="" # Default to blank, let the cluster discover it if possible
ENV_NAME="ppk5d"
DATASET_PATH=""

# Source common utilities (local copy)
source "$(dirname "$0")/hpc_common.sh"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 -d <DATASET_PATH> [options]"
    echo ""
    echo "Transfers processing scripts and submits a batch job."
    echo ""
    echo "Options:"
    echo "  -d, --dataset <Path>  (Required) Path to the experiment folder on the HPC."
    echo "  -H, --host <Host>      HPC hostname (Default: ${HPC_LOGIN})"
    echo "  -h, --home <Path>      HPC home path override."
    echo "  -e, --env <Env>        Python venv name (Default: ${ENV_NAME})"
    echo "  --help                 Show this help message"
    echo ""
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) show_usage; exit 0 ;;
        -d|--dataset) DATASET_PATH="$2"; shift; shift ;;
        -H|--host) HPC_LOGIN="$2"; shift; shift ;;
        -h|--home) HPC_HOME="$2"; shift; shift ;;
        -e|--env) ENV_NAME="$2"; shift; shift ;;
        *) echo "❌ Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

if [ -z "$DATASET_PATH" ]; then
    echo "❌ Error: DATASET_PATH is required."
    echo "Example: $0 -d /mmfs2/scratch/user/cell1"
    exit 1
fi

validate_host "$HPC_LOGIN" || exit 1

# Files to transfer
SCRIPTS=("generate_config.py" "process_job.py" "submit_compute_job.sbatch" "run_bigtiff_cropper.m")

# Check for existence locally
for script in "${SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        echo "❌ Error: Could not find $script in the current directory."
        exit 1
    fi
done

# Discover HPC Home if not provided
if [ -z "$HPC_HOME" ]; then
    echo "📡 Discovering home directory on ${HPC_LOGIN}..."
    HPC_HOME=$(ssh -q "${HPC_LOGIN}" "echo \$HOME")
    if [ -z "$HPC_HOME" ]; then
        echo "❌ Error: Could not reach ${HPC_LOGIN} to discover home directory."
        exit 1
    fi
fi

echo "🚀 Starting workflow for ${HPC_LOGIN}:${DATASET_PATH}"
echo "   HPC HOME: ${HPC_HOME}"

# --- Step 1: Transfer Scripts ---
echo "➡️  (1/2) Transferring scripts to ${HPC_LOGIN}..."
if ! scp "${SCRIPTS[@]}" "${HPC_LOGIN}:${HPC_HOME}/"; then
    echo "❌ ERROR: File transfer failed."
    exit 1
fi
echo "✅ Scripts transferred."

# --- Step 2: Submit Job ---
echo "➡️  (2/2) Submitting Slurm job..."
EXPORT_VARS="ALL,DATASET_PATH=${DATASET_PATH},HPC_HOME=${HPC_HOME},ENV_NAME=${ENV_NAME}"

SUBMIT_OUT=$(ssh "${HPC_LOGIN}" "sbatch --export=${EXPORT_VARS} ${HPC_HOME}/submit_compute_job.sbatch")

if [ $? -eq 0 ]; then
    echo "✅ Success!"
    echo "   ${SUBMIT_OUT}"
else
    echo "❌ ERROR: sbatch submission failed."
    exit 1
fi

echo "----------------------------------------------------------------"
echo "✅ Local script finished."