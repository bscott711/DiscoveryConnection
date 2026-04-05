#!/bin/bash
# reconnect_hpc_jupyter.sh
#
# A script to find a running HPC Jupyter session,
# rebuild the SSH tunnel, and reconnect.

# --- Configuration & Defaults ---
LOCAL_PORT="9999"
HPC_HOST="Discovery"
JOB_ID=""

# Source common utilities
source "$(dirname "$0")/hpc_common.sh"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Finds and reconnects to a running JupyterLab session (macOS only)."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>    HPC host (Default: ${HPC_HOST})"
    echo "                       Options: Discovery, Innovator"
    echo "  -j, --job <JOB_ID>   (Optional) A specific Job ID to reconnect to."
    echo "                       (Default: finds the latest running jupyter job)"
    echo "  -h, --help           Show this help message and exit"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -H Innovator -j 12345"
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help) show_usage; exit 0 ;;
        -H|--host) HPC_HOST="$2"; shift; shift ;;
        -j|--job) JOB_ID="$2"; shift; shift ;;
        *) echo "❌ Error: Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

# --- Validation ---
validate_host "$HPC_HOST" || exit 1

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ Error: This script uses 'osascript' and is currently macOS-only."
    exit 1
fi

echo "🔎 Searching for Jupyter job on ${HPC_HOST}..."

# --- Find Job ID ---
if [ -z "$JOB_ID" ]; then
    # If no Job ID is provided, find the latest running job with "jupyter-" in its name
    JOB_ID=$(ssh ${HPC_HOST} "squeue -u \$USER -o '%.i %.j' -h | grep 'jupyter-' | sort -n -k1 | tail -n 1 | awk '{print \$1}'")
    
    if [ -z "$JOB_ID" ]; then
        echo "❌ Error: No running 'jupyter-' jobs found for user on ${HPC_HOST}."
        exit 1
    fi
    echo "✅ Found latest running job: ${JOB_ID}"
else
    # If Job ID was provided, just confirm it's running
    STATUS=$(ssh ${HPC_HOST} "squeue -j ${JOB_ID} -h -o %T" 2>/dev/null) || STATUS="UNKNOWN"
    if [[ "$STATUS" != "RUNNING" ]]; then
        echo "❌ Error: Job ${JOB_ID} is not currently running (status: $STATUS)."
        exit 1
    fi
    echo "✅ Confirmed job ${JOB_ID} is running."
fi

# --- Find Log File ---
LOG_FILE_NAME=$(ssh ${HPC_HOST} "ls -1 ~/logs/jupyter-*-${JOB_ID}.log" 2>/dev/null | head -n 1)

if [ -z "$LOG_FILE_NAME" ]; then
    echo "❌ Error: Could not find log file for job ${JOB_ID} in ~/logs/"
    exit 1
fi

echo "📄 Using log file: ${LOG_FILE_NAME}"

# --- Get Connection Details ---
echo "⏳ Fetching connection details..."

NODE=$(ssh ${HPC_HOST} "squeue -j ${JOB_ID} -h -o %N" 2>/dev/null)
JUPYTER_URL=$(ssh ${HPC_HOST} "grep 'http://127.0.0.1' ${LOG_FILE_NAME} | head -n 1 | grep -o 'http://[^ ]*'")
PORT=$(echo ${JUPYTER_URL} | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
TOKEN=$(echo ${JUPYTER_URL} | sed -n 's|.*token=\([^ ]*\).*|\1|p')
FINAL_URL="http://localhost:${LOCAL_PORT}/?token=${TOKEN}"

if [ -z "$NODE" ] || [ -z "$PORT" ] || [ -z "$TOKEN" ]; then
    echo "❌ Error: Could not parse connection details for job ${JOB_ID}."
    echo "   Node: ${NODE:-UNKNOWN}, Port: ${PORT:-UNKNOWN}"
    exit 1
fi

echo "✅ Connection details found: Node=${NODE}, Port=${PORT}"

# --- Rebuild Tunnel ---
SESSION_NAME="hpc-tunnel-${JOB_ID}"
start_tmux_tunnel "${SESSION_NAME}" "${HPC_HOST}" "${NODE}" "${LOCAL_PORT}" "${PORT}"

sleep 2
echo "🚀 Opening JupyterLab in your default browser..."
open "${FINAL_URL}"

echo ""
echo "------------------------------------------------------------------"
echo "✅ Reconnection complete."
echo "   A new terminal window has opened and is running your SSH tunnel."
echo "   URL: ${FINAL_URL}"
echo ""
echo "   When finished, stop everything with:"
echo "   ./kill_hpc_jupyter.sh -H ${HPC_HOST} -j ${JOB_ID}"
echo "------------------------------------------------------------------"