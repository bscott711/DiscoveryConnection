#!/bin/bash
# kill_hpc_jupyter.sh
#
# A script to clean up the HPC Jupyter session.
# It stops the remote Slurm job and the local tmux tunnel session.

# --- Defaults ---
HPC_HOST="Discovery"
JOB_ID=""

# Source common utilities
source "$(dirname "$0")/hpc_common.sh"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options] <JOB_ID>"
    echo ""
    echo "Stops the remote Slurm job and the local tmux tunnel session."
    echo ""
    echo "Options:"
    echo "  -j, --job <JOB_ID>   The Slurm Job ID to cancel."
    echo "  -H, --host <Host>    HPC host (Default: ${HPC_HOST})"
    echo "                       Options: Discovery, Innovator"
    echo "  -h, --help           Show this help message and exit"
    echo ""
    echo "Examples:"
    echo "  $0 3256"
    echo "  $0 -j 3256"
    echo "  $0 -H Innovator 12345"
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help) show_usage; exit 0 ;;
        -j|--job) JOB_ID="$2"; shift; shift ;;
        -H|--host) HPC_HOST="$2"; shift; shift ;;
        *) 
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                JOB_ID="$1"
                shift
            else
                echo "❌ Error: Unknown option: $1"
                show_usage
                exit 1
            fi
            ;;
    esac
done

# --- Validation ---
if [ -z "$JOB_ID" ]; then
    echo "❌ Error: Job ID is required."
    show_usage
    exit 1
fi

validate_host "$HPC_HOST" || exit 1

# --- Main Logic ---
SESSION_NAME="hpc-tunnel-${JOB_ID}"

echo "🧹 Starting cleanup for Job ID: ${JOB_ID} on ${HPC_HOST}"
echo "--------------------------------------------------"

# Step 1: Stop the remote Slurm job
echo "➡️  Stopping remote Jupyter job on ${HPC_HOST}..."
if ! ssh -o ConnectTimeout=5 "${HPC_HOST}" "scancel ${JOB_ID}" 2>/dev/null; then
    echo "⚠️  Warning: Could not reach ${HPC_HOST} to cancel job. Is your SSH/VPN active?"
fi

# Step 2: Stop the local tmux session holding the SSH tunnel
echo "➡️  Stopping local SSH tunnel session (${SESSION_NAME})..."

if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    tmux kill-session -t "${SESSION_NAME}"
    echo "✅ Local tunnel session stopped."
else
    echo "⚠️  Local tunnel session not found. It may have already been stopped."
fi

echo "--------------------------------------------------"
echo "✅ Cleanup complete."