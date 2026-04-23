#!/bin/bash
# start_hpc_jupyter_matlab.sh
#
# Starts JupyterLab on the HPC with a persistent MATLAB server for PetaKit.

# --- Configuration & Defaults ---
LOCAL_PORT="9999"
HPC_HOST="Discovery"
ENV_NAME="ppk5d"
PARTITION="" # Default empty for auto-select
MEMORY="128"
TIME="08:00:00"
CPUS="8"
GRES="gpu:1"

# Source common utilities
source "$(dirname "$0")/hpc_common.sh"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Starts a JupyterLab session + MATLAB server on the HPC."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>       HPC host (Default: ${HPC_HOST})"
    echo "  -e, --env <Env>         Your venv name (Default: ${ENV_NAME})"
    echo "  -p, --partition <Part>  Slurm partition (Default: ${PARTITION})"
    echo "                          Available on Discovery: all-gpu, compute, gpu"
    echo "  -m, --mem <Memory>      Memory in GB (Default: ${MEMORY})"
    echo "  -t, --time <Time>       Job time limit (Default: ${TIME})"
    echo "  -c, --cpus <CPUs>       Number of CPU cores (Default: ${CPUS})"
    echo "  -g, --gres <GRES>       GPU resources (Default: ${GRES})"
    echo "  -h, --help              Show help"
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

# Ensure partition is lowercase (Slurm is case-sensitive)
PARTITION=$(echo "$PARTITION" | tr '[:upper:]' '[:lower:]')

# Handle GRES format (ensure gpu: prefix if only a number is given)
if echo "$GRES" | grep -qE '^[0-9]+$'; then
    GRES="gpu:${GRES}"
fi

# --- Auto-select partition if not provided ---
if [[ -z "$PARTITION" ]]; then
    log_info "Auto-selecting partition with ${CPUS} CPUs and ${MEMORY}GB RAM..."
    # If GRES is set, prefer GPU partitions
    PREFER_GPU="false"
    if [[ -n "$GRES" ]]; then PREFER_GPU="true"; fi

    PARTITION=$(find_available_partition "$HPC_HOST" "$CPUS" "$MEMORY" "$PREFER_GPU")
    if [[ $? -ne 0 ]]; then
        log_warn "No idle resources found meeting requirements. Defaulting to 'gpu' partition."
        PARTITION="gpu"
    fi
fi

# Final safety check: if we ended up in compute but GRES is set, we must clear GRES
if [[ "$PARTITION" == "compute"* ]]; then
    if [[ -n "$GRES" ]]; then
        log_warn "Partition '$PARTITION' does not support GPUs. Disabling GPU request for this job."
        GRES=""
    fi
fi

# --- MATLAB Configuration ---
IFS=':' read -r MATLAB_MODULE MATLAB_ROOT <<< "$(get_matlab_config "$HPC_HOST")"

# --- Find Local Port ---
LOCAL_PORT=$(find_available_port $LOCAL_PORT) || exit 1
echo "🌐 Using local port: ${LOCAL_PORT}"

# --- Final Prep ---
MEMORY_GB="${MEMORY}G"
JOB_NAME="jupyter-${ENV_NAME}"

echo "🚀 Starting job with settings:"
echo "   Host:         ${HPC_HOST}"
echo "   Environment:  ${ENV_NAME}"
echo "   Partition:    ${PARTITION:-[AUTO]}"
echo "   Resources:    ${CPUS} CPUs, ${MEMORY_GB} Mem, GPUs: ${GRES:-None}, ${TIME}"

# --- Main Logic ---
echo "📁 Ensuring 'logs' directory exists..."
ssh ${HPC_HOST} "mkdir -p ~/logs"

echo "⏳ Submitting JupyterLab + MATLAB job..."

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

# --- Compute-node variables ---
export node=\$(hostname -s)
export port=\$((8000 + RANDOM % 2000))

ENV_NAME_PASSED="${ENV_NAME}"
SOFTWARE_PATH="\$HOME/software"

# --- Module Loading ---
module load pypetakit5d
module load ${MATLAB_MODULE}

# --- MATLAB ENV FIX ---
${MATLAB_ENV_SETUP}

# --- Python Isolation & Path ---
echo "Injecting local projects from \${SOFTWARE_PATH}"
export PYTHONPATH="\${SOFTWARE_PATH}:\${PYTHONPATH}"
export PATH="\$HOME/\${ENV_NAME_PASSED}/bin:\$PATH"

# --- START PETAKIT SERVER ---
echo "🚀 Launching persistent MATLAB server in background..."
LOG_PATH="\$HOME/logs/matlab-server-\${SLURM_JOB_ID}.log"

# Run MATLAB headlessly
nohup matlab -nodisplay -nosplash -r "addpath(genpath('\${SOFTWARE_PATH}')); try, run_petakit_server; catch ME, disp(getReport(ME)); exit(1); end" > \$LOG_PATH 2>&1 &
# --- END PETAKIT SERVER ---

echo "Launching JupyterLab on node \$node, port \$port..."
\$HOME/\${ENV_NAME_PASSED}/bin/python -m jupyter lab --no-browser --ip=127.0.0.1 --port=\$port
SBATCH_SCRIPT
)

if [ -z "$JOB_ID" ]; then
    echo "❌ Failed to submit job. Exiting."
    exit 1
fi

echo "✅ Job submitted with ID: ${JOB_ID}"
LOG_FILE="logs/${JOB_NAME}-${JOB_ID}.log"
echo "⏳ Waiting for job to start..."

while true;
do
    # Fetch Status (%T) and Reason (%r)
    SLURM_LINE=$(ssh ${HPC_HOST} "squeue -j ${JOB_ID} -h -o '%T|%r'" 2>/dev/null)
    
    if [[ -n "$SLURM_LINE" ]]; then
        STATUS=$(echo "$SLURM_LINE" | awk -F'|' '{print $1}')
        REASON=$(echo "$SLURM_LINE" | awk -F'|' '{print $2}')
        
        if [[ "$STATUS" != "PENDING" && "$STATUS" != "RUNNING" ]]; then
            echo -e "\n❌ Job ${JOB_ID} is in status ${STATUS}. Check output with:"
            echo "   ssh ${HPC_HOST} 'cat ~/${LOG_FILE}'"
            exit 1
        fi
        echo -ne "\r⏳ Job ${JOB_ID} is ${STATUS} (${REASON})...          "
    else
        # If job is not in squeue, check if it finished or failed
        if ! ssh ${HPC_HOST} "[[ -f ~/${LOG_FILE} ]]"; then
            echo -e "\n❌ Job ${JOB_ID} is no longer in queue and log file not found."
            exit 1
        fi
    fi

    if ssh ${HPC_HOST} "grep -q 'http://127.0.0.1' ~/${LOG_FILE} 2>/dev/null"; then
        echo "" # Move to next line after status loop
        break
    fi
    sleep 5
done

echo "✅ Your server is ready!"
NODE=$(ssh ${HPC_HOST} "grep 'Launching JupyterLab on node' ~/${LOG_FILE} | sed 's/.*node //;s/,.*//'")
JUPYTER_URL=$(ssh ${HPC_HOST} "grep 'http://127.0.0.1' ~/${LOG_FILE} | head -n 1 | grep -o 'http://[^ ]*'")
PORT=$(echo ${JUPYTER_URL} | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
TOKEN=$(echo ${JUPYTER_URL} | sed -n 's|.*token=\([^ ]*\).*|\1|p')
FINAL_URL="http://localhost:${LOCAL_PORT}/?token=${TOKEN}"

start_tmux_tunnel "hpc-tunnel-${JOB_ID}" "${HPC_HOST}" "${NODE}" "${LOCAL_PORT}" "${PORT}"

sleep 2
echo "🚀 Opening JupyterLab..."
open "${FINAL_URL}"

echo ""
echo "------------------------------------------------------------------"
echo "✅ Session active. Logs are at:"
echo "   Jupyter:       ~/logs/${JOB_NAME}-${JOB_ID}.log"
echo "   MATLAB Server: ~/logs/matlab-server-${JOB_ID}.log"
echo ""
echo "   URL: ${FINAL_URL}"
echo ""
echo "   To Stop: ./kill_hpc_jupyter.sh -H ${HPC_HOST} -j ${JOB_ID}"
echo "------------------------------------------------------------------"
