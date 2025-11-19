#!/bin/bash
#
# A local script to launch the persistent MATLAB PetaKit worker on the HPC.
# Run this from your laptop/desktop.
#

# --- Defaults ---
HPC_HOST="Discovery"
PARTITION="compute"
CPUS="48"
MEMORY="250" # GB
TIME="2-00:00:00" # 2 Days
GRES="gpu:0"

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Launches a headless MATLAB worker on the cluster to process PetaKit jobs."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>       HPC host (Default: ${HPC_HOST})"
    echo "  -p, --partition <Part>  Slurm partition (Default: ${PARTITION})"
    echo "  -c, --cpus <CPUs>       Number of CPU cores (Default: ${CPUS})"
    echo "  -m, --mem <Memory>      Memory in GB (Default: ${MEMORY})"
    echo "  -t, --time <Time>       Job time limit (Default: ${TIME})"
    echo "  -g, --gres <GRES>       GPU resources (Default: ${GRES})"
    echo "  -h, --help              Show this help message"
    echo ""
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help) show_usage; exit 0 ;;
        -H|--host) HPC_HOST="$2"; shift; shift ;;
        -p|--partition) PARTITION="$2"; shift; shift ;;
        -c|--cpus) CPUS="$2"; shift; shift ;;
        -m|--mem) MEMORY="$2"; shift; shift ;;
        -t|--time) TIME="$2"; shift; shift ;;
        -g|--gres) GRES="$2"; shift; shift ;;
        *) echo "❌ Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

MEMORY_GB="${MEMORY}G"
JOB_NAME="petakit-worker"

echo "🚀 Launching PetaKit Worker on ${HPC_HOST}..."
echo "   CPUs: ${CPUS} | Mem: ${MEMORY_GB} | Time: ${TIME}"

# --- Remote Execution ---
# We construct the SBATCH script here and pipe it via SSH
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

# --- Define Variables ---
HPC_HOST_PASSED="${HPC_HOST}"
SOFTWARE_PATH="\$HOME/software"

echo "Starting Worker on \$(hostname)"
echo "Cluster: \${HPC_HOST_PASSED}"

# --- Module Loading ---
module load pypetakit5d

# Host-Specific Logic
if [[ "\${HPC_HOST_PASSED}" == "Discovery" ]]; then
    module load matlab/R2024b
elif [[ "\${HPC_HOST_PASSED}" == "Innovator" ]]; then
    module load matlab/R2023b
fi

# --- MATLAB Environment Fix ---
echo "✅ Setting up MATLAB environment..."
MATLAB_ROOT="/cm/shared/apps_local/matlab/R2024B"
export LD_LIBRARY_PATH="\${MATLAB_ROOT}/runtime/glnxa64:\${MATLAB_ROOT}/bin/glnxa64:\${MATLAB_ROOT}/sys/os/glnxa64:\${MATLAB_ROOT}/sys/opengl/lib/glnxa64:\${LD_LIBRARY_PATH}"
export MW_MCR_ROOT="\${MATLAB_ROOT}"

# --- Launch Server ---
echo "🚀 Launching MATLAB server (blocking)..."
export MATLABPATH="\${SOFTWARE_PATH}:\${MATLABPATH}"

# Run blocking (no '&') so Slurm keeps the allocation alive
matlab -nodisplay -nosplash -r "addpath(genpath('\${SOFTWARE_PATH}')); try, run_petakit_server; catch ME, disp(getReport(ME)); exit(1); end; exit;"

echo "🛑 Server exited."
SBATCH_EOF
)

if [ -z "$JOB_ID" ]; then
    echo "❌ Failed to submit job."
    exit 1
fi

echo "✅ Worker submitted successfully!"
echo "   Job ID:  ${JOB_ID}"
echo "   Log:     ~/logs/worker-${JOB_ID}.log"
echo ""
echo "To check status run locally:"
echo "   ssh ${HPC_HOST} 'squeue -j ${JOB_ID}'"