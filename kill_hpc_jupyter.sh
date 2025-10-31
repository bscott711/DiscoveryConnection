#!/bin/bash
#
# A script to clean up the HPC Jupyter session.
# It stops the remote Slurm job and the local tmux tunnel session.
#

# --- Defaults ---
HPC_HOST="Discovery"
JOB_ID=""

# --- Help Function ---
show_usage() {
    echo "Usage: $0 -j <JOB_ID> [options]"
    echo ""
    echo "Stops the remote Slurm job and the local tmux tunnel session."
    echo ""
    echo "Required Argument:"
    echo "  -j, --job <JOB_ID>   The Slurm Job ID to cancel."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>    HPC host (Default: ${HPC_HOST})"
    echo "                       Options: Discovery, Innovator"
    echo "  -h, --help           Show this help message and exit"
    echo ""
    echo "Example:"
    echo "  $0 -j 3256"
    echo "  $0 -H Innovator -j 12345"
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_usage
            exit 0
            ;;
        -j|--job)
            JOB_ID="$2"
            shift # past argument
            shift # past value
            ;;
        -H|--host)
            HPC_HOST="$2"
            shift # past argument
            shift # past value
            ;;
        *)    # unknown option
            echo "❌ Error: Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# --- Validate Arguments ---
if [ -z "$JOB_ID" ]; then
    echo "❌ Error: Job ID is required."
    show_usage
    exit 1
fi

case "$HPC_HOST" in
    Discovery|Innovator)
        # Valid, do nothing
        ;;
    *)
        echo "❌ Error: Invalid host '$HPC_HOST'."
        echo "Please use 'Discovery' or 'Innovator'."
        exit 1
        ;;
esac

# --- Main Logic ---
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