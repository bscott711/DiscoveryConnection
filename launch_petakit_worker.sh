#!/bin/bash
#
# Smart launcher for the persistent MATLAB PetaKit worker.
# Automatically handles environment differences between clusters.
# Compatible with macOS (Bash 3.2) and Linux.
#

# --- Defaults ---
HPC_HOST="Discovery"
PARTITION="compute"
CPUS="48"
MEMORY="250"
TIME="2-00:00:00"
GRES="gpu:0"
PETAKIT_PATH="/cm/shared/apps_local/petakit5d" # Default shared path

# --- Help Function ---
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Launches a headless MATLAB worker on the cluster."
    echo ""
    echo "Options:"
    echo "  -H, --host <Host>       HPC host (Default: ${HPC_HOST})"
    echo "  -p, --partition <Part>  Slurm partition (Default: ${PARTITION})"
    echo "  -c, --cpus <CPUs>       Number of CPU cores (Default: ${CPUS})"
    echo "  -m, --mem <Memory>      Memory in GB (Default: ${MEMORY})"
    echo "  -t, --time <Time>       Job time limit (Default: ${TIME})"
    echo "  -g, --gres <GRES>       GPU resources (Default: ${GRES})"
    echo "  -k, --kit-path <Path>   Path to PetaKit5D on the cluster"
    echo "                          (Default: ${PETAKIT_PATH})"
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
        -k|--kit-path) PETAKIT_PATH="$2"; shift; shift ;;
        *) echo "❌ Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

# --- Configuration Lookup ---
case "$HPC_HOST" in
    "Discovery")
        TARGET_MODULE="matlab/R2024b"
        TARGET_ROOT="/cm/shared/apps_local/matlab/R2024b"
        ;;
    "Innovator")
        TARGET_MODULE="matlab/R2023b"
        TARGET_ROOT="/cm/shared/apps_local/matlab/R2023b"
        ;;
    *)
        echo "❌ Error: Unknown host '$HPC_HOST'. No MATLAB config found."
        exit 1
        ;;
esac

MEMORY_GB="${MEMORY}G"
JOB_NAME="petakit-worker"

echo "🚀 Launching PetaKit Worker on ${HPC_HOST}..."
echo "   Config:  ${TARGET_MODULE}"
echo "   PetaKit: ${PETAKIT_PATH}"
echo "   Resources: ${CPUS} CPUs, ${MEMORY_GB} Mem, ${TIME}"

# --- Remote Execution ---
# We pipe the script via SSH, injecting the resolved paths
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

# --- Export Variables for MATLAB ---
# This allows run_petakit_server.m to find PetaKit without hardcoding
export PETAKIT_ROOT="${PETAKIT_PATH}"
export SLURM_CPUS_PER_TASK=${CPUS} 

# --- Module Loading ---
echo "Loading modules..."
module load pypetakit5d
module load ${TARGET_MODULE}

# --- MATLAB Environment Fix ---
echo "✅ Setting up MATLAB environment for ${HPC_HOST}..."
MATLAB_ROOT="${TARGET_ROOT}"
export LD_LIBRARY_PATH="\${MATLAB_ROOT}/runtime/glnxa64:\${MATLAB_ROOT}/bin/glnxa64:\${MATLAB_ROOT}/sys/os/glnxa64:\${MATLAB_ROOT}/sys/opengl/lib/glnxa64:\${LD_LIBRARY_PATH}"
export MW_MCR_ROOT="\${MATLAB_ROOT}"

# --- Launch Server ---
echo "🚀 Launching MATLAB server (blocking)..."
SOFTWARE_PATH="\$HOME/software"

# Add software path to MATLAB's search path
export MATLABPATH="\${SOFTWARE_PATH}:\${MATLABPATH}"

# Run blocking
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
echo "To check status:"
echo "   ssh ${HPC_HOST} 'squeue -j ${JOB_ID}'"

echo ""
echo "To stop:"
echo "   ssh ${HPC_HOST} 'scancel ${JOB_ID}'"
