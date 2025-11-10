#!/bin/bash
#
# A script to start JupyterLab on the HPC, automatically create the
# local SSH tunnel, and open the URL in the default browser.
#

# --- Configuration & Defaults ---
LOCAL_PORT="9999"
HPC_HOST="Discovery"
ENV_NAME="ppk5d" # Default personal venv name
PARTITION="gpu"
MEMORY="128"
TIME="08:00:00"
CPUS="8"
GRES="gpu:1"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Starts a JupyterLab session on the HPC, creates an SSH tunnel, and opens it."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>       HPC host (Default: ${HPC_HOST})"
    echo "                          Options: Discovery, Innovator"
    echo "  -e, --env <Env>         Your personal venv name (Default: ${ENV_NAME})"
    echo "  -p, --partition <Part>  Slurm partition (Default: ${PARTITION})"
    echo "  -m, --mem <Memory>      Memory to request in GB (Default: ${MEMORY})"
    echo "  -t, --time <Time>       Job time limit (Default: ${TIME})"
    echo "  -c, --cpus <CPUs>       Number of CPU cores (Default: ${CPUS})"
    echo "  -g, --gres <GRES>       GPU resources (Default: ${GRES})"
    echo "  -h, --help              Show this help message and exit"
    echo ""
    echo "Example:"
    echo "  $0 -p all-gpu -m 64 -t 08:00:00 -c 16 -g gpu:2"
}

# --- Argument Parsing ---
# This loop processes arguments in any order
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
        -e|--env)
            ENV_NAME="$2"
            shift # past argument
            shift # past value
            ;;
        -p|--partition)
            PARTITION="$2"
            shift # past argument
            shift # past value
            ;;
        -m|--mem)
            MEMORY="$2"
            shift # past argument
            shift # past value
            ;;
        -t|--time)
            TIME="$2"
            shift # past argument
            shift # past value
            ;;
        -c|--cpus)
            CPUS="$2"
            shift # past argument
            shift # past value
            ;;
        -g|--gres)
            GRES="$2"
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

# --- Validate Host ---
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

# --- Final variable prep ---
MEMORY_GB="${MEMORY}G" # Add the 'G' for sbatch
JOB_NAME="jupyter-${ENV_NAME}" # Dynamic job name

echo "🚀 Starting job with settings:"
echo "   Host:         ${HPC_HOST}"
echo "   Environment:  ${ENV_NAME} (at ~/${ENV_NAME}/bin/activate)"
echo "   Partition:    ${PARTITION}"
echo "   Memory:       ${MEMORY_GB}"
echo "   Time:         ${TIME}"
echo "   CPUs:         ${CPUS}"
echo "   GPUs:         ${GRES}"


# --- Main Logic ---
echo "📁 Ensuring 'logs' directory exists on ${HPC_HOST}..."
ssh ${HPC_HOST} "mkdir -p ~/logs"

echo "⏳ Submitting JupyterLab job to ${HPC_HOST}..."

# --- (JOB SUBMISSION BLOCK) ---
JOB_ID=$(ssh ${HPC_HOST} "sbatch --parsable" <<SBATCH_SCRIPT
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --partition=${PARTITION}
#SBATCH --gres=${GRES}
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --time=${TIME}
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
# Path to the venv's site-packages
VENV_SITE_PACKAGES="\$HOME/\${ENV_NAME_PASSED}/lib/python3.11/site-packages"
# Path to your local software directory
SOFTWARE_PATH="\$HOME/software"


# --- Use the variables ---
echo "Preparing JupyterLab on node \$node, port \$port"
echo "Running on cluster: \${HPC_HOST_PASSED}"
echo "Using environment: ${ENV_NAME}"

# --- Module Loading ---
# Load base modules first
echo "Loading PyPetaKit5D module (for jupyter)..."
module load pypetakit5d

echo "Loading MATLAB module..."
if [[ "\${HPC_HOST_PASSED}" == "Discovery" ]]; then
    module load matlab/R2024b
elif [[ "\${HPC_HOST_PASSED}" == "Innovator" ]]; then
    module load matlab/R2023b
fi

# --- Extend Python's Path ---
# Instead of activating the venv, which conflicts with conda,
# just add its site-packages to the PYTHONPATH.
echo "Injecting venv packages from \${VENV_SITE_PACKAGES}"
echo "Injecting local projects from \${SOFTWARE_PATH}"
export PYTHONPATH="\${VENV_SITE_PACKAGES}:\${SOFTWARE_PATH}:\${PYTHONPATH}"

echo "Launching JupyterLab..."
# Run the base module's python, which can now find your
# packages (like jupyter-matlab-proxy) via PYTHONPATH.
python -m jupyter lab --no-browser --ip=127.0.0.1 --port=\$port
SBATCH_SCRIPT
)
# --- (End of job submission block) ---

if [ -z "$JOB_ID" ]; then
    echo "❌ Failed to submit job. Exiting."
    exit 1
fi

echo "✅ Job submitted with ID: ${JOB_ID}"
# Use the dynamic log file name, now inside the 'logs' folder
LOG_FILE="logs/${JOB_NAME}-${JOB_ID}.log"
echo "⏳ Waiting for job to start and URL to be ready (checking ~/${LOG_FILE})..."

while true;
do
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
SSH_COMMAND="ssh -N -o StrictHostKeyChecking=no -L ${LOCAL_PORT}:localhost:${PORT} -J ${HPC_HOST} ${NODE}"

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
echo "STEP 2: If you close your laptop or the tunnel breaks, run this"
echo "        script to find the job and reconnect:"
echo ""
echo "   ./reconnect_hpc_jupyter.sh -H ${HPC_HOST}"
echo ""
echo "STEP 3: When finished, stop everything with:"
echo ""
echo "   ./kill_hpc_jupyter.sh -H ${HPC_HOST} -j ${JOB_ID}"
echo "------------------------------------------------------------------"