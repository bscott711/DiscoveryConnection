#!/bin/bash
#
# A script to clean up the HPC Jupyter session.
# It stops the remote Slurm job and the local tmux tunnel session.
#

# --- Configuration ---
HPC_HOST="Discovery"

# --- Main Logic ---
# Check if a Job ID was provided as an argument
if [ -z "${1}" ]; then
    echo "❌ Error: No Job ID provided."
    echo "Usage: ./kill_hpc_jupyter.sh <JOB_ID>"
    exit 1
fi

JOB_ID="${1}"
SESSION_NAME="hpc-tunnel-${JOB_ID}"

echo "🧹 Starting cleanup for Job ID: ${JOB_ID}"
echo "--------------------------------------------------"

# Step 1: Stop the remote Slurm job
echo "➡️  Stopping remote Jupyter job on ${HPC_HOST}..."
ssh "${HPC_HOST}" "scancel ${JOB_ID}"

# Step 2: Stop the local tmux session holding the SSH tunnel
echo "➡️  Stopping local SSH tunnel session (${SESSION_NAME})..."

# Check if the tmux session exists before trying to kill it
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    tmux kill-session -t "${SESSION_NAME}"
    echo "✅ Local tunnel session stopped."
else
    echo "⚠️  Local tunnel session not found. It may have already been stopped."
fi

echo "--------------------------------------------------"
echo "✅ Cleanup complete."