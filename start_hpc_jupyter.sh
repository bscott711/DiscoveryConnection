#!/bin/bash
#
# A script to start JupyterLab on the HPC, automatically create the
# local SSH tunnel, and open the URL in the default browser.
#
# Usage: ./start_hpc_jupyter.sh [Host] [Env] [Partition] [Memory]
# Defaults: Host=Discovery, Env=ppk5d, Partition=gpu, Memory=128
#

# --- Configuration ---
LOCAL_PORT="9999"

# --- Argument Handling ---
# Hostname (Default to Discovery if $1 is omitted)
if [ -z "$1" ]; then
    echo "ℹ️ No host specified. Defaulting to Discovery."
    HPC_HOST="Discovery"
else
    case "$1" in
        Discovery)
            HPC_HOST="Discovery"
            ;;
        Innovator)
            HPC_HOST="Innovator"
            ;;
        *)
            echo "❌ Error: Invalid host '$1'."
            echo "Please use 'Discovery' or 'Innovator'."
            exit 1
            ;;
    esac
fi

# Environment Name (Default to ppk5d if $2 is omitted)
if [ -z "$2" ]; then
    if [ ! -z "$1" ]; then
      echo "ℹ️ No environment name specified. Defaulting to ppk5d."
    fi
    ENV_NAME="ppk5d"
else
    ENV_NAME="$2"
fi

# Partition (Default to gpu if $3 is omitted)
if [ -z "$3" ]; then
    PARTITION="gpu"
else
    PARTITION="$3"
fi

# Memory (Default to 128G if $4 is omitted)
if [ -z "$4" ]; then
    MEMORY="128"
else
    MEMORY="$4"
fi
MEMORY_GB="${MEMORY}G" # Add the 'G' for sbatch

echo "🚀 Starting job with settings:"
echo "   Host:         ${HPC_HOST}"
echo "   Environment:  ${ENV_NAME} (at ~/${ENV_NAME}/bin/activate)"
echo "   Partition:    ${PARTITION}"
echo "   Memory:       ${MEMORY_GB}"

# --- Main Logic ---
echo "📁 Ensuring 'logs' directory exists on ${HPC_HOST}..."
ssh ${HPC_HOST} "mkdir -p ~/logs"

echo "⏳ Submitting JupyterLab job to ${HPC_HOST}..."

# --- (JOB SUBMISSION BLOCK) ---
# This block pipes the script directly to sbatch.
# Variables like ${ENV_NAME} are expanded LOCALLY.
# Variables like \$node are ESCAPED locally, sent to sbatch,
# and expanded on the COMPUTE NODE.
JOB_ID=$(ssh ${HPC_HOST} "sbatch --parsable" <<SBATCH_SCRIPT
#!/bin/bash
#SBATCH --job-name=jupyter-${ENV_NAME}
#SBATCH --partition=${PARTITION}
#SBATCH --gres=gpu:1
#SBATCH --time=04:00:00
#SBATCH --mem=${MEMORY_GB}
#SBATCH --output=logs/%x-%j.log
#SBATCH --open-mode=truncate

unset XDG_RUNTIME_DIR

# --- Define compute-node variables ---
export node=\$(hostname -s)
export port=\$((8000 + RANDOM % 2000))

# --- Define variables for logic ---
# These are "baked in" by the local shell
HPC_HOST_PASSED="${HPC_HOST}"
ENV_NAME_PASSED="${ENV_NAME}"
# This one is mixed: \$HOME is from compute node, \${ENV_NAME} is local
expanded_env_path="\$HOME/\${ENV_NAME_PASSED}/bin/activate"


# --- Use the variables ---
echo "Preparing JupyterLab on node \$node, port \$port"
echo "Running on cluster: \${HPC_HOST_PASSED}"
echo "Using environment: \${ENV_NAME_PASSED}"

# --- Module Loading and Activation in Correct Order ---

echo "Loading Python module..."
module load python/3.11

echo "Loading MATLAB module..."
if [[ "\${HPC_HOST_PASSED}" == "Discovery" ]]; then
    module load matlab/R2024b
elif [[ "\${HPC_HOST_PASSED}" == "Innovator" ]]; then
    module load matlab/R2023b
fi

echo "Activating Python environment..."
if [ ! -f "\${expanded_env_path}" ]; then
    echo "❌ ERROR: Environment activation script not found at \${expanded_env_path}"
    exit 1
fi
source "\${expanded_env_path}"

echo "Launching JupyterLab..."
jupyter lab --no-browser --ip=127.0.0.1 --port=\$port
SBATCH_SCRIPT
)
# --- (End of job submission block) ---

if [ -z "$JOB_ID" ]; then
    echo "❌ Failed to submit job. Exiting."
    exit 1
fi

echo "✅ Job submitted with ID: ${JOB_ID}"
# Use the dynamic log file name, now inside the 'logs' folder
LOG_FILE="logs/jupyter-${ENV_NAME}-${JOB_ID}.log"
echo "⏳ Waiting for job to start and URL to be ready (checking ~/${LOG_FILE})..."

while true; do
    STATUS=$(ssh ${HPC_HOST} "squeue -j ${JOB_ID} -h -o %T" 2>/dev/null) || STATUS="UNKNOWN"
    if [[ "$STATUS" != "PENDING" && "$STATUS" != "RUNNING" ]]; then
        echo "❌ Job ${JOB_ID} is no longer running (status: $STATUS). Check output with:"
        echo "   ssh ${HPC_HOST} 'cat ~/${LOG_FILE}'"
        exit 1
    fi
    if ssh ${HPC_HOST} "[ -f ~/${LOG_FILE} ]"; then
        if ssh ${HPC_HOST} "grep -q 'http://127.0.0.1' ~/${LOG_FILE}"; then
            break
        fi
    fi
    sleep 5
done

echo "✅ Your server is ready!"
NODE=$(ssh ${HPC_HOST} "grep 'Preparing JupyterLab on node' ~/${LOG_FILE} | sed 's/.*node //;s/,.*//'")
JUPYTER_URL=$(ssh ${HPC_HOST} "grep 'http://127.0.0.1' ~/${LOG_FILE} | head -n 1 | grep -o 'http://[^ ]*'")
PORT=$(echo ${JUPYTER_URL} | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
TOKEN=$(echo ${JUPYTER_URL} | sed -n 's|.*token=\([^ ]*\).*|\1|p')
FINAL_URL="http://localhost:${LOCAL_PORT}/?token=${TOKEN}"

echo "Tunneling is being set up in a new terminal window..."
SESSION_NAME="hpc-tunnel-${JOB_ID}"
SSH_COMMAND="ssh -N -L ${LOCAL_PORT}:localhost:${PORT} -J ${HPC_HOST} ${NODE}"

osascript <<EOF
tell application "Terminal"
    activate
    do script "tmux new -s ${SESSION_NAME} '${SSH_COMMAND}'"
end tell
EOF

sleep 2
echo "🚀 Opening JupyterLab in your default browser..."
open "${FINAL_URL}"

echo ""
echo "------------------------------------------------------------------"
echo "✅ A new terminal window has opened and is running your SSH tunnel."
echo "   You can safely close this original window."
echo ""
echo "STEP 1: If it didn't open automatically, copy this URL into your browser:"
echo ""
echo "   ${FINAL_URL}"
echo ""
echo "STEP 2: When finished, stop everything with:"
echo ""
# Corrected kill command to match the new parameterized script
echo "   ./kill_hpc_jupyter.sh ${HPC_HOST} ${JOB_ID} "
echo "------------------------------------------------------------------"