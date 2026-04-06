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
    echo "Usage: $0 [options] [JOB_ID]"
    echo ""
    echo "Stops the remote Slurm job and the local tmux tunnel session."
    echo ""
    echo "Options:"
    echo "  -j, --job <JOB_ID>   The Slurm Job ID to cancel."
    echo "  -H, --host <Host>    HPC host (Default: ${HPC_HOST})"
    echo "                       Options: Discovery, Innovator"
    echo "  -h, --help           Show help"
    echo ""
    echo "Note: If no Job ID is provided, it will search for the latest"
    echo "Jupyter job across both Discovery and Innovator."
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
validate_host "$HPC_HOST" || exit 1

# --- Find Job ID if not provided ---
if [ -z "$JOB_ID" ]; then
    echo "🔎 Searching for latest Jupyter job on ${HPC_HOST}..."
    JOB_ID=$(ssh ${HPC_HOST} "squeue -u \$USER -o '%.i %.j' -h | grep 'jupyter-' | sort -n -k1 | tail -n 1 | awk '{print \$1}'")
    
    if [ -z "$JOB_ID" ]; then
        OTHER_HOST="Innovator"
        if [ "$HPC_HOST" == "Innovator" ]; then OTHER_HOST="Discovery"; fi
        
        echo "🔍 No job found on ${HPC_HOST}. Trying ${OTHER_HOST}..."
        JOB_ID=$(ssh ${OTHER_HOST} "squeue -u \$USER -o '%.i %.j' -h | grep 'jupyter-' | sort -n -k1 | tail -n 1 | awk '{print \$1}'")
        
        if [ -n "$JOB_ID" ]; then
            HPC_HOST=$OTHER_HOST
            echo "✅ Found job ${JOB_ID} on ${HPC_HOST}"
        else
            echo "❌ Error: No running 'jupyter-' jobs found for user on Discovery or Innovator."
            exit 1
        fi
    else
        echo "✅ Found latest running job: ${JOB_ID}"
    fi
fi

# --- Main Logic ---
SESSION_NAME="hpc-tunnel-${JOB_ID}"

echo "🧹 Starting cleanup for Job ID: ${JOB_ID} on ${HPC_HOST}"
echo "--------------------------------------------------"

# Step 1: Stop the remote Slurm job
echo "➡️  Stopping remote Jupyter job on ${HPC_HOST}..."
if ! ssh -o ConnectTimeout=5 "${HPC_HOST}" "scancel ${JOB_ID}" 2>/dev/null; then
    # Try the other host just in case the Job ID was for the other one
    OTHER_HOST="Innovator"
    if [ "$HPC_HOST" == "Innovator" ]; then OTHER_HOST="Discovery"; fi
    
    echo "🔍 Could not cancel on ${HPC_HOST}. Checking ${OTHER_HOST}..."
    if ! ssh -o ConnectTimeout=5 "${OTHER_HOST}" "scancel ${JOB_ID}" 2>/dev/null; then
        echo "⚠️  Warning: Job ${JOB_ID} not found or host unreachable."
    else
        echo "✅ Job ${JOB_ID} cancelled on ${OTHER_HOST}."
    fi
else
    echo "✅ Remote job cancelled."
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