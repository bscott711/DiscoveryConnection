#!/bin/bash
# start_hpc_jupyter.sh
#
# A script to start JupyterLab on the HPC, automatically create the
# local SSH tunnel, and open the URL in the default browser.

# --- Configuration & Defaults ---
LOCAL_PORT="9999"
HPC_HOST="Discovery"
ENV_NAME="ppk5d" # Default personal venv name
PARTITION="compute"
MEMORY="8"
TIME="12:00:00"
CPUS="1"
GRES="gpu:0"

# Source common utilities
source "$(dirname "$0")/hpc_common.sh"

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
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help) show_usage; exit 0 ;;
        -H|--host) HPC_HOST="$2"; shift; shift ;;
        -e|--env) ENV_NAME="$2"; shift; shift ;;
        -p|--partition) PARTITION="$2"; shift; shift ;;
        -m|--mem) MEMORY="$2"; shift; shift ;;
        -t|--time) TIME="$2"; shift; shift ;;
        -c|--cpus) CPUS="$2"; shift; shift ;;
        -g|--gres) GRES="$2"; shift; shift ;;
        *) echo "❌ Error: Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

# --- Validation ---
validate_host "$HPC_HOST" || exit 1

# --- Configure MATLAB based on Host ---
IFS=':' read -r MATLAB_MODULE MATLAB_ROOT <<< "$(get_matlab_config "$HPC_HOST")"

# --- Find an available local port ---
LOCAL_PORT=$(find_available_port $LOCAL_PORT) || exit 1
echo "🌐 Using local port: ${LOCAL_PORT}"

# --- Final variable prep ---
MEMORY_GB="${MEMORY}G"
JOB_NAME="jupyter-${ENV_NAME}"

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

# Fetch MATLAB env setup script for the remote side
MATLAB_ENV_SETUP=$(get_matlab_env_setup "$MATLAB_ROOT")

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
ENV_NAME_PASSED="${ENV_NAME}"
SOFTWARE_PATH="\$HOME/software"

# --- Use the variables ---
echo "Preparing JupyterLab on node \$node, port \$port"
echo "Using environment: ${ENV_NAME}"

# --- Module Loading ---
echo "Loading PyPetaKit5D module (for jupyter)..."
module load pypetakit5d

echo "Loading MATLAB module (${MATLAB_MODULE})..."
module load ${MATLAB_MODULE}

# --- MATLAB ENV FIX ---
${MATLAB_ENV_SETUP}

# --- ISOLATE JUPYTER CONFIG ---
echo "🧹 Cleaning up global Jupyter and Python paths..."
unset PYTHONHOME
unset JUPYTER_PATH
unset JUPYTER_CONFIG_DIR
unset JUPYTER_DATA_DIR

# --- STRICT PYTHON ISOLATION ---
echo "🛡️ Enforcing local Python isolation..."
export PYTHONPATH="\${SOFTWARE_PATH}"
export PATH="\$HOME/\${ENV_NAME_PASSED}/bin:\$PATH"

echo "Launching JupyterLab..."
\$HOME/\${ENV_NAME_PASSED}/bin/python -m jupyter lab --no-browser --ip=127.0.0.1 --port=\$port
SBATCH_SCRIPT
)

if [ -z "$JOB_ID" ]; then
    echo "❌ Failed to submit job. Exiting."
    exit 1
fi

echo "✅ Job submitted with ID: ${JOB_ID}"
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

SESSION_NAME="hpc-tunnel-${JOB_ID}"
start_tmux_tunnel "${SESSION_NAME}" "${HPC_HOST}" "${NODE}" "${LOCAL_PORT}" "${PORT}"

sleep 2
echo "🚀 Opening JupyterLab in your default browser..."
open "${FINAL_URL}"

echo ""
echo "------------------------------------------------------------------"
echo "✅ A new terminal window has opened and is running your SSH tunnel."
echo "   You can safely close this original window."
echo ""
echo "STEP 1: If it didn't open automatically, copy this URL into your browser:"
echo "   ${FINAL_URL}"
echo ""
echo "STEP 2: If you close your laptop or the tunnel breaks, run this"
echo "        script to find the job and reconnect:"
echo "   ./reconnect_hpc_jupyter.sh -H ${HPC_HOST} -j ${JOB_ID}"
echo ""
echo "STEP 3: When finished, stop everything with:"
echo "   ./kill_hpc_jupyter.sh -H ${HPC_HOST} -j ${JOB_ID}"
echo "------------------------------------------------------------------"
