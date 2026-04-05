#!/bin/bash
# launch_petakit_worker.sh
#
# Launches a headless MATLAB worker for PetaKit processing.

# --- Defaults ---
HPC_HOST="Discovery"
ENV_NAME="ppk5d"
PARTITION="compute"
CPUS="48"
MEMORY="250"
TIME="2-00:00:00"
GRES="gpu:0"
PETAKIT_PATH="/cm/shared/apps_local/petakit5d"
FOLLOW_LOG=true

# Source common utilities
source "$(dirname "$0")/hpc_common.sh"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Launches a headless MATLAB worker on the cluster."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>       HPC host (Default: ${HPC_HOST})"
    echo "  -e, --env <Env>         Local venv name (Default: ${ENV_NAME})"
    echo "  -p, --partition <Part>  Slurm partition (Default: ${PARTITION})"
    echo "  -c, --cpus <CPUs>       Number of CPU cores (Default: ${CPUS})"
    echo "  -m, --mem <Memory>      Memory in GB (Default: ${MEMORY})"
    echo "  -t, --time <Time>       Job time limit (Default: ${TIME})"
    echo "  -g, --gres <GRES>       GPU resources (Default: ${GRES})"
    echo "  -k, --kit-path <Path>   Path to PetaKit5D on the cluster"
    echo "                          (Default: ${PETAKIT_PATH})"
    echo "  --no-log-follow         Don't tail the log after submission"
    echo "  -h, --help              Show help"
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -H|--host) HPC_HOST="$2"; shift; shift ;;
        -e|--env) ENV_NAME="$2"; shift; shift ;;
        -p|--partition) PARTITION="$2"; shift; shift ;;
        -c|--cpus) CPUS="$2"; shift; shift ;;
        -m|--mem) MEMORY="$2"; shift; shift ;;
        -t|--time) TIME="$2"; shift; shift ;;
        -g|--gres) GRES="$2"; shift; shift ;;
        -k|--kit-path) PETAKIT_PATH="$2"; shift; shift ;;
        --no-log-follow) FOLLOW_LOG=false; shift ;;
        *) echo "❌ Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

# --- Validation ---
validate_host "$HPC_HOST" || exit 1

# --- MATLAB Config ---
IFS=':' read -r MATLAB_MODULE MATLAB_ROOT <<< "$(get_matlab_config "$HPC_HOST")"

MEMORY_GB="${MEMORY}G"
JOB_NAME="petakit-worker"

echo "🚀 Launching PetaKit Worker on ${HPC_HOST}..."
echo "   Config:      ${MATLAB_MODULE}"
echo "   Environment: ${ENV_NAME}"
echo "   PetaKit:     ${PETAKIT_PATH}"
echo "   Resources:   ${CPUS} CPUs, ${MEMORY_GB} Mem, ${TIME}"

# --- Remote Execution ---
echo "📁 Ensuring 'logs' directory exists..."
ssh ${HPC_HOST} "mkdir -p ~/logs"

MATLAB_ENV_SETUP=$(get_matlab_env_setup "$MATLAB_ROOT")

JOB_ID=$(ssh ${HPC_HOST} "sbatch --parsable" <<SBATCH_EOF
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --partition=${PARTITION}
#SBATCH --gres=${GRES}
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --mem=${MEMORY_GB}
#SBATCH --time=${TIME}
#SBATCH --output=logs/worker-%j.log
#SBATCH --open-mode=truncate

export PETAKIT_ROOT="${PETAKIT_PATH}"
export SLURM_CPUS_PER_TASK=${CPUS} 

# --- Module Loading ---
module load pypetakit5d
module load ${MATLAB_MODULE}

# --- PYTHON ENVIRONMENT SETUP ---
ENV_NAME="${ENV_NAME}"
SOFTWARE_PATH="\$HOME/software"
VENV_ROOT="\$HOME/\${ENV_NAME}"

# Detect Python version in venv
PYTHON_VER=\$(ls \${VENV_ROOT}/lib | grep python3. | head -n 1)
VENV_SITE_PACKAGES="\${VENV_ROOT}/lib/\${PYTHON_VER}/site-packages"

export PYTHONPATH="\${VENV_SITE_PACKAGES}:\${SOFTWARE_PATH}:\${PYTHONPATH}"
export PATH="\${VENV_ROOT}/bin:\$PATH"

# Create a wrapper for MATLAB subprocesses
WRAPPER_SCRIPT="\$HOME/logs/python_wrapper_\${SLURM_JOB_ID}.sh"
cat <<WRAPPER_EOF > "\${WRAPPER_SCRIPT}"
#!/bin/bash
export PYTHONPATH="\${VENV_SITE_PACKAGES}:\${SOFTWARE_PATH}:\${PYTHONPATH}"
exec "\${VENV_ROOT}/bin/python" "\\\$@"
WRAPPER_EOF
chmod +x "\${WRAPPER_SCRIPT}"
export OPYM_PYTHON="\${WRAPPER_SCRIPT}"

# --- MATLAB ENVIRONMENT ---
${MATLAB_ENV_SETUP}
export MATLABPATH="\${SOFTWARE_PATH}:\${MATLABPATH}"

# --- Launch Server ---
echo "🚀 Launching MATLAB server (blocking)..."
matlab -nodisplay -nosplash -r "addpath(genpath('\${SOFTWARE_PATH}')); try, run_petakit_server; catch ME, disp(getReport(ME)); exit(1); end; exit;"
SBATCH_EOF
)

if [ -z "$JOB_ID" ]; then
    echo "❌ Failed to submit job."
    exit 1
fi

LOG_FILE="logs/worker-${JOB_ID}.log"

echo "✅ Worker submitted! ID: ${JOB_ID}"
echo "   Log: ~/logs/worker-${JOB_ID}.log"

if [ "$FOLLOW_LOG" = true ]; then
    echo "📡 Waiting for log file to appear..."
    COUNT=0
    while ! ssh -q ${HPC_HOST} "[ -f ~/${LOG_FILE} ]"; do
        if [ $COUNT -ge 20 ]; then
            echo "⚠️  Log file not found yet. The job is likely still queued."
            exit 0
        fi
        sleep 3
        ((COUNT++))
    done
    echo "✅ Streaming output (Ctrl+C to stop trailing):"
    ssh ${HPC_HOST} "tail -f ~/${LOG_FILE}"
fi