#!/bin/bash
#
# A script to start JupyterLab on the HPC, automatically create the
# local SSH tunnel, and open the URL in the default browser.
#

# --- Configuration ---
HPC_HOST="Discovery"
LOCAL_PORT="9999"

# --- Main Logic ---
echo "🚀 Submitting JupyterLab job to the HPC..."

# Submit the Slurm job
JOB_ID=$(ssh ${HPC_HOST} 'bash -l -c "
    sbatch --parsable <<\\EOF
#!/bin/bash
#SBATCH --job-name=jupyter-session
#SBATCH --partition=all-gpu
#SBATCH --gres=gpu:1
#SBATCH --time=04:00:00
#SBATCH --mem=128G
#SBATCH --output=%x-%j.log
#SBATCH --open-mode=truncate

unset XDG_RUNTIME_DIR
node=\$(hostname -s)
port=\$(shuf -i 8000-9999 -n 1)

echo \"Preparing JupyterLab on node \$node, port \$port\"

module load python/3.11
module load matlab/R2024b
source ~/ppk5d/bin/activate

# Set the MATLAB Runtime library path
# export LD_LIBRARY_PATH=\$(dirname \$(dirname \$(which matlab)))/runtime/glnxa64:\$LD_LIBRARY_PATH

# Launch JupyterLab
jupyter lab --no-browser --ip=127.0.0.1 --port=\$port
EOF
"')

if [ -z "$JOB_ID" ]; then
    echo "❌ Failed to submit job. Exiting."
    exit 1
fi

echo "✅ Job submitted with ID: ${JOB_ID}"

LOG_FILE="jupyter-session-${JOB_ID}.log"
echo "⏳ Waiting for job to start and URL to be ready..."

while true; do
    # First, check if the job is still running
    STATUS=$(ssh ${HPC_HOST} "squeue -j ${JOB_ID} -h -o %T" 2>/dev/null) || STATUS="UNKNOWN"

    if [[ "$STATUS" != "PENDING" && "$STATUS" != "RUNNING" ]]; then
        echo "❌ Job ${JOB_ID} is no longer running (status: $STATUS). Check output with:"
        echo "   ssh ${HPC_HOST} 'cat ~/jupyter-session-${JOB_ID}.log'"
        exit 1
    fi

    # Check if log file exists before grepping
    if ssh ${HPC_HOST} "[ -f ~/${LOG_FILE} ]"; then
        # Now check if the URL line is present
        if ssh ${HPC_HOST} "grep -q 'http://127.0.0.1' ~/${LOG_FILE}"; then
            break
        fi
    fi

    # Not ready yet
    sleep 5
done

echo "✅ Your server is ready!"

# --- Fetch Connection Details ---
NODE=$(ssh ${HPC_HOST} "grep 'Preparing JupyterLab on node' ~/${LOG_FILE} | sed 's/.*node //;s/,.*//'")
JUPYTER_URL=$(ssh ${HPC_HOST} "grep 'http://127.0.0.1' ~/${LOG_FILE} | head -n 1 | grep -o 'http://[^ ]*'")
PORT=$(echo ${JUPYTER_URL} | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
TOKEN=$(echo ${JUPYTER_URL} | sed -n 's|.*token=\([^ ]*\).*|\1|p')
FINAL_URL="http://localhost:${LOCAL_PORT}/?token=${TOKEN}"

# --- Automate SSH Tunnel Creation ---
echo "Tunneling is being set up in a new terminal window..."

SESSION_NAME="hpc-tunnel-${JOB_ID}"
SSH_COMMAND="ssh -N -L ${LOCAL_PORT}:localhost:${PORT} -J ${HPC_HOST} ${NODE}"

osascript <<EOF
tell application "Terminal"
    activate
    do script "tmux new -s ${SESSION_NAME} '${SSH_COMMAND}'"
end tell
EOF

# Give the tunnel a moment to establish before opening the browser
sleep 2

# --- Automatically Open Browser ---
echo "🚀 Opening JupyterLab in your default browser..."
open "${FINAL_URL}"

# --- Final Instructions ---
echo ""
echo "------------------------------------------------------------------"
echo "✅ A new terminal window has opened and is running your SSH tunnel."
echo "   You can safely close this original window."
echo ""
echo "STEP 1: If it didn't open automatically, copy this URL into your browser:"
echo ""
echo "   ${FINAL_URL}"
echo ""
echo "STEP 2: When you are finished, stop everything with this command"
echo "        in a new terminal:"
echo ""
echo "   ./kill_hpc_jupyter.sh ${JOB_ID}"
echo "------------------------------------------------------------------"
