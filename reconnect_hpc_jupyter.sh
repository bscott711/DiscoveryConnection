#!/bin/bash
#
# A script to find a running HPC Jupyter session,
# rebuild the SSH tunnel, and reconnect.
#

# --- Configuration & Defaults ---
LOCAL_PORT="9999"
HPC_HOST="Discovery"
JOB_ID=""

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Finds and reconnects to a running JupyterLab session."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>    HPC host (Default: ${HPC_HOST})"
    echo "                       Options: Discovery, Innovator"
    echo "  -j, --job <JOB_ID>   (Optional) A specific Job ID to reconnect to."
    echo "                       (Default: finds the latest running jupyter job)"
    echo "  -h, --help           Show this help message and exit"
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_usage
            exit 0
            ;;
        -H|--host)
            HPC_HOST="$2"
            shift # past argument
            shift # past value
            ;;
        -j|--job)
            JOB_ID="$2"
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
# Use wildcard to find the log file regardless of ENV_NAME
LOG_FILE_NAME=$(ssh ${HPC_HOST} "ls -1 ~/logs/jupyter-*-${JOB_ID}.log" 2>/dev/null)

if [ -z "$LOG_FILE_NAME" ]; then
    echo "❌ Error: Could not find log file for job ${JOB_ID} in ~/logs/"
    exit 1
fi

LOG_FILE_PATH="~/${LOG_FILE_NAME##*/}" # Get just the 'logs/...' part

echo "📄 Using log file: ${LOG_FILE_NAME}"

# --- Get Connection Details ---
echo "⏳ Fetching connection details..."

# 1. Get Node Name via squeue (most reliable method)
# %N gives the Node List for the job ID.
NODE=$(ssh ${HPC_HOST} "squeue -j ${JOB_ID} -h -o %N" 2>/dev/null)

# 2. Get URL, Port, and Token from the log file (which is successful)
JUPYTER_URL=$(ssh ${HPC_HOST} "grep 'http://127.0.0.1' ${LOG_FILE_NAME} | head -n 1 | grep -o 'http://[^ ]*'")
PORT=$(echo ${JUPYTER_URL} | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
TOKEN=$(echo ${JUPYTER_URL} | sed -n 's|.*token=\([^ ]*\).*|\1|p')
FINAL_URL="http://localhost:${LOCAL_PORT}/?token=${TOKEN}"

if [ -z "$NODE" ]; then
    echo "❌ Error: Could not find the compute node name (squeue returned empty)."
    echo "   Job Status might be Pending or Missing."
    exit 1
fi

if [ -z "$PORT" ] || [ -z "$TOKEN" ]; then
    echo "❌ Error: Could not parse URL/Port/Token from log file (${LOG_FILE_NAME})."
    echo "   Node: ${NODE}"
    echo "   Port: ${PORT}"
    echo "   Token: ${TOKEN}"
    exit 1
fi

echo "✅ Connection details found: Node=${NODE}, Port=${PORT}"

# --- Rebuild Tunnel ---
SESSION_NAME="hpc-tunnel-${JOB_ID}"

# First, kill any old, dead session with the same name
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    echo "🧹 Found old tunnel session. Killing it..."
    tmux kill-session -t "${SESSION_NAME}"
fi

echo "🚀 Starting new tunnel in tmux session '${SESSION_NAME}'..."
SSH_COMMAND="ssh -N -o StrictHostKeyChecking=no -L ${LOCAL_PORT}:localhost:${PORT} -J ${HPC_HOST} ${NODE}"

osascript <<EOF
tell application "Terminal"
    activate
    do script "tmux new -s ${SESSION_NAME} '${SSH_COMMAND}'"
end tell
EOF

sleep 2

# --- Open Browser ---
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