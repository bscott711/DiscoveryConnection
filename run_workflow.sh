#!/bin/bash
#
# This script transfers necessary files to the HPC and submits the Slurm job.
# It includes basic error checking.
set -e # Exit immediately if any command fails

# --- Configuration ---
HPC_LOGIN="Discovery"
HPC_HOME="/home/SDSMT.LOCAL/bscott"

# Local names of the files to transfer
LOCAL_CONFIG_SCRIPT="generate_config.py"
LOCAL_JOB_SCRIPT="process_job.py"
LOCAL_SBATCH_SCRIPT="submit_compute_job.sbatch"

# Remote path for the sbatch script
REMOTE_SBATCH_SCRIPT="$HPC_HOME/$LOCAL_SBATCH_SCRIPT"

# --- Main Script ---
echo "--- (1/3) Transferring local scripts to $HPC_LOGIN ---"
# Transfer all three files
scp $LOCAL_CONFIG_SCRIPT $LOCAL_JOB_SCRIPT $LOCAL_SBATCH_SCRIPT ${HPC_LOGIN}:${HPC_HOME}/
if [ $? -ne 0 ]; then
    echo "❌ ERROR: File transfer (scp) failed."
    exit 1
fi
echo "✅ Files transferred successfully."

echo "--- (2/3) Connecting to $HPC_LOGIN to submit Slurm job ---"
# Use SSH to execute the sbatch command remotely
ssh $HPC_LOGIN "sbatch $REMOTE_SBATCH_SCRIPT"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: SSH command or remote sbatch submission failed."
    exit 1
fi

echo "--- (3/3) Slurm job submitted! Monitor progress on the cluster. ---"
echo "--- Local script finished. ---"