#!/bin/bash
# tail_petakit_worker.sh
#
# A script to tail the log of a running PetaKit worker on the HPC.

# --- Defaults ---
HPC_HOST="Discovery"
JOB_ID=""

# Source common utilities
source "$(dirname "$0")/hpc_common.sh"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options] [JOB_ID]"
    echo ""
    echo "Tails the output log of a PetaKit worker."
    echo ""
    echo "Options:"
    echo "  -j, --job <JOB_ID>   The Slurm Job ID to tail."
    echo "                       (Default: finds the latest 'petakit-worker' job)"
    echo "  -H, --host <Host>    HPC host (Default: ${HPC_HOST})"
    echo "                       Options: Discovery, Innovator"
    echo "  -h, --help           Show help"
    echo ""
    echo "Examples:"
    echo "  $0                  # Tail latest worker on default host"
    echo "  $0 12345            # Tail specific Job ID"
    echo "  $0 -H Innovator     # Tail latest worker on Innovator"
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
                show_usage; exit 1
            fi
            ;;
    esac
done

# --- Validation ---
validate_host "$HPC_HOST" || exit 1

# --- Find Job ID if not provided ---
if [ -z "$JOB_ID" ]; then
    echo "🔎 Searching for latest 'petakit-worker' job on ${HPC_HOST}..."
    JOB_ID=$(ssh ${HPC_HOST} "squeue -u \$USER -o '%.i %.j' -h | grep 'petakit-worker' | sort -n -k1 | tail -n 1 | awk '{print \$1}'")
    
    if [ -z "$JOB_ID" ]; then
        # Try other host
        OTHER_HOST="Innovator"
        if [ "$HPC_HOST" == "Innovator" ]; then OTHER_HOST="Discovery"; fi
        echo "🔍 No job on ${HPC_HOST}. Trying ${OTHER_HOST}..."
        JOB_ID=$(ssh ${OTHER_HOST} "squeue -u \$USER -o '%.i %.j' -h | grep 'petakit-worker' | sort -n -k1 | tail -n 1 | awk '{print \$1}'")
        
        if [ -n "$JOB_ID" ]; then
            HPC_HOST=$OTHER_HOST
            echo "✅ Found job ${JOB_ID} on ${HPC_HOST}"
        else
            echo "❌ Error: No running 'petakit-worker' jobs found for user on Discovery or Innovator."
            exit 1
        fi
    else
        echo "✅ Found latest job: ${JOB_ID}"
    fi
fi

LOG_FILE="logs/worker-${JOB_ID}.log"

# Check if log file exists
if ! ssh -q ${HPC_HOST} "[ -f ~/${LOG_FILE} ]"; then
    echo "❌ Error: Log file ~/${LOG_FILE} not found on ${HPC_HOST}."
    exit 1
fi

echo "📡 Streaming ~/${LOG_FILE} from ${HPC_HOST}..."
echo "   (Press Ctrl+C to stop trailing)"
echo "----------------------------------------------------------------"
ssh ${HPC_HOST} "tail -f ~/${LOG_FILE}"
