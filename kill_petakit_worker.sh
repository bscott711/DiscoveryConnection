#!/bin/bash
# kill_petakit_worker.sh
#
# A script to stop a standalone MATLAB PetaKit worker job on the HPC.

# --- Defaults ---
HPC_HOST="Discovery"
JOB_ID=""

# Source common utilities
source "$(dirname "$0")/hpc_common.sh"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options] [JOB_ID]"
    echo ""
    echo "Stops a remote MATLAB PetaKit worker job."
    echo ""
    echo "Options:"
    echo "  -j, --job <JOB_ID>   The Slurm Job ID to cancel."
    echo "                       (Default: finds the latest 'petakit-worker' job)"
    echo "  -H, --host <Host>    HPC host (Default: ${HPC_HOST})"
    echo "                       Options: Discovery, Innovator"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 12345"
    echo "  $0 -H Innovator"
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
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
    echo "🔎 Searching for 'petakit-worker' job on ${HPC_HOST}..."
    JOB_ID=$(ssh ${HPC_HOST} "squeue -u \$USER -o '%.i %.j' -h | grep 'petakit-worker' | sort -n -k1 | tail -n 1 | awk '{print \$1}'")
    
    if [ -z "$JOB_ID" ]; then
        echo "❌ Error: No running 'petakit-worker' jobs found for user on ${HPC_HOST}."
        exit 1
    fi
    echo "✅ Found latest job: ${JOB_ID}"
fi

# --- Main Logic ---
echo "🧹 Stopping PetaKit worker Job ID: ${JOB_ID} on ${HPC_HOST}..."

if ssh -o ConnectTimeout=5 "${HPC_HOST}" "scancel ${JOB_ID}" 2>/dev/null; then
    echo "✅ Job ${JOB_ID} cancelled successfully."
else
    echo "⚠️  Warning: Could not reach ${HPC_HOST} or job ${JOB_ID} not found."
fi
