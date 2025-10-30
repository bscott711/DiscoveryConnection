#!/bin/bash
#SBATCH --job-name=PetaKit5D_Compute
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=240G
#SBATCH --time=48:00:00
#SBATCH --output=compute_job_%j.log
#SBATCH --error=compute_job_%j.err

#SBATCH --mail-user=brandon.scott@sdsmt.edu
#SBATCH --mail-type=END,FAIL             # Send email on job END or FAIL

# --- ADD THIS LINE ---
set -e # Exit immediately if any command fails

# --- Commands to run on the allocated compute node ---

echo "Job $SLURM_JOB_ID started on compute node $(hostname) at $(date)"
echo "Using $SLURM_CPUS_PER_TASK CPUs on node $SLURM_NODELIST"

# Define remote script paths
HPC_HOME="/home/SDSMT.LOCAL/bscott"
REMOTE_CONFIG_SCRIPT="$HPC_HOME/generate_config.py"
REMOTE_JOB_SCRIPT="$HPC_HOME/process_job.py"

echo "--- Activating Python environment ---"
source $HPC_HOME/ppk5d/bin/activate
if [ $? -ne 0 ]; then echo "❌ ERROR: Failed to activate Python environment."; exit 1; fi

echo "--- Running Python config generator ---"
python $REMOTE_CONFIG_SCRIPT
if [ $? -ne 0 ]; then echo "❌ ERROR: Config generator script failed."; exit 1; fi
echo "✅ Config generated."

echo "--- Running Python job script (locally on node with $SLURM_CPUS_PER_TASK cores) ---"
python $REMOTE_JOB_SCRIPT
if [ $? -ne 0 ]; then echo "❌ ERROR: Job processing script failed."; exit 1; fi
echo "✅ Job script finished."

echo "Job $SLURM_JOB_ID finished successfully at $(date)"
