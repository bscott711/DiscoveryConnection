#!/bin/bash
#
# A script to clean up the HPC Jupyter session.
# It stops the remote Slurm job and the local tmux tunnel session.
#
# Usage: ./kill_hpc_jupyter.sh [Discovery | Innovator] <JOB_ID>
#

# --- Variable Definitions ---
HPC_HOST=""
JOB_ID=""

# --- Argument Parsing ---
if [ -z "$1" ]; then
    echo "❌ Error: No Job ID provided."
    echo "Usage: ./kill_hpc_jupyter.sh [Discovery | Innovator] <JOB_ID>"
    exit 1
fi

# Check if the first argument is a host name
case "$1" in
    Discovery)
        HPC_HOST="Discovery"
        # If host is provided, Job ID must be the second argument
        if [ -z "$2" ]; then
            echo "❌ Error: Host specified but no Job ID provided."
            echo "Usage: ./kill_hpc_jupyter.sh ${HPC_HOST} <JOB_ID>"
            exit 1
        fi
        JOB_ID="$2"
        ;;
    Innovator)
        HPC_HOST="Innovator"
        # If host is provided, Job ID must be the second argument
        if [ -z "$2" ]; then
            echo "❌ Error: Host specified but no Job ID provided."
            echo "Usage: ./kill_hpc_jupyter.sh ${HPC_HOST} <JOB_ID>"
            exit 1
        fi
        JOB_ID="$2"
        ;;
    *)
        # First argument is not a known host, assume it's the Job ID
        echo "ℹ️ No host specified. Defaulting to Discovery."
        HPC_HOST="Discovery"
        JOB_ID="$1"
        ;;
esac

SESSION_NAME="hpc-tunnel-${JOB_ID}"

echo "🧹 Starting cleanup for Job ID: ${JOB_ID} on ${HPC_HOST}"
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
