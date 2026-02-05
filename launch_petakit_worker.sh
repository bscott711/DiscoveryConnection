#!/bin/bash
#
# Smart launcher for the persistent MATLAB PetaKit worker.
# Automatically handles environment differences between clusters.
# Compatible with macOS (Bash 3.2) and Linux.
#

# --- Defaults ---
HPC_HOST="Discovery"
ENV_NAME="ppk5d"
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
    echo "  -e, --env <Env>         Local venv name (Default: ${ENV_NAME})"
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
        -e|--env) ENV_NAME="$2"; shift; shift ;;
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
echo "   Config:      ${TARGET_MODULE}"
echo "   Environment: ${ENV_NAME}"
echo "   PetaKit:     ${PETAKIT_PATH}"
echo "   Resources:   ${CPUS} CPUs, ${MEMORY_GB} Mem, ${TIME}"

# --- Remote Execution ---
echo "📁 Ensuring 'logs' directory exists..."
ssh ${HPC_HOST} "mkdir -p ~/logs"

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

# --- PYTHON ENVIRONMENT FIX ---
# Instead of full activation (which can conflict), we inject paths 
# directly into PYTHONPATH, matching your working Jupyter script.

ENV_NAME="${ENV_NAME}"
SOFTWARE_PATH="\$HOME/software"

# 1. Dynamically find the site-packages in the user's venv (handles 3.11 vs 3.12 automatically)
#    We look for the first directory matching 'python3.*' inside the lib folder.
VENV_SITE_PACKAGES=\$(find \$HOME/\${ENV_NAME}/lib -maxdepth 1 -name "python3.*" -type d | head -n 1)/site-packages

echo "🔧 Injecting Python Paths:"
echo "   - Local Software: \${SOFTWARE_PATH}"
echo "   - Venv Packages:  \${VENV_SITE_PACKAGES}"

# 2. Configure PYTHONPATH (for this shell)
export PYTHONPATH="\${VENV_SITE_PACKAGES}:\${SOFTWARE_PATH}:\${PYTHONPATH}"

# 3. Create a Wrapper Script
#    MATLAB sometimes sanitizes environment variables when spawning subprocesses.
#    We create a wrapper script that enforces PYTHONPATH for the execution.

# --- FIX: Detect correct Python binary from VENV to prevent 3.11 vs 3.12 mismatch ---
# VENV_SITE_PACKAGES is like: /path/to/venv/lib/python3.11/site-packages
# Use bash string manipulation to find root (safer than nested dirname)
# Note: We escape '$' (e.g. \${VAR}) so this logic runs ON THE CLUSTER, not your local Mac.

# 1. Strip /site-packages
_tmp_path="\${VENV_SITE_PACKAGES%/*}"
# 2. Strip /pythonX.Y
_tmp_path="\${_tmp_path%/*}"
# 3. Strip /lib
VENV_ROOT="\${_tmp_path%/*}"

REAL_PYTHON=""
if [ -n "\${VENV_ROOT}" ] && [ -f "\${VENV_ROOT}/bin/python" ]; then
    REAL_PYTHON="\${VENV_ROOT}/bin/python"
    echo "🐍 Using Virtual Environment Python: \${REAL_PYTHON}"
else
    REAL_PYTHON=\$(which python)
    echo "⚠️ Venv Python not found at '\${VENV_ROOT}/bin/python', using system Python: \${REAL_PYTHON}"
fi
# ------------------------------------------------------------------------------------

# Ensure logs directory exists (Use \$HOME to ensure we use the Cluster's home dir)
mkdir -p "\$HOME/logs"

WRAPPER_SCRIPT="\$HOME/logs/python_wrapper_\${SLURM_JOB_ID:-unknown}.sh"

echo "📝 Generating Python Wrapper: \${WRAPPER_SCRIPT}"
cat <<WRAPPER_EOF > "\${WRAPPER_SCRIPT}"
#!/bin/bash
# Enforce PYTHONPATH which might be lost in MATLAB subprocesses
export PYTHONPATH="\${VENV_SITE_PACKAGES}:\${SOFTWARE_PATH}:\${PYTHONPATH}"
exec "\${REAL_PYTHON}" "\\\$@"
WRAPPER_EOF

chmod +x "\${WRAPPER_SCRIPT}"

# 4. Point MATLAB to use this wrapper instead of the raw python binary
export OPYM_PYTHON="\${WRAPPER_SCRIPT}"

# --- VERIFY PYTHON ENVIRONMENT ---
echo "----------------------------------------------------------------"
echo "🔍 Verifying Python Environment (via Wrapper)..."
echo "   Wrapper:    \${OPYM_PYTHON}"
echo "   Real Py:    \${REAL_PYTHON}"

# Execute verification using the WRAPPER to ensure it works
\${OPYM_PYTHON} -c "
import sys
import os
print(f'   Version:    {sys.version.split()[0]}')
print('   sys.path (first 3):')
for p in sys.path[:3]:
    print(f'      - {p}')

print('\n   Checking Imports:')
try:
    import opym
    print(f'   ✅ opym:     Found (Namespace/Module)')
except ImportError as e:
    print(f'   ❌ opym:     FAILED ({e})')

try:
    import opym.cli
    print(f'   ✅ opym.cli: Found at {os.path.dirname(opym.cli.__file__)}')
except ImportError as e:
    print(f'   ❌ opym.cli: FAILED ({e})')
"
echo "----------------------------------------------------------------"

# --- MATLAB Environment Fix ---
echo "✅ Setting up MATLAB environment for ${HPC_HOST}..."
MATLAB_ROOT="${TARGET_ROOT}"
export LD_LIBRARY_PATH="\${MATLAB_ROOT}/runtime/glnxa64:\${MATLAB_ROOT}/bin/glnxa64:\${MATLAB_ROOT}/sys/os/glnxa64:\${MATLAB_ROOT}/sys/opengl/lib/glnxa64:\${LD_LIBRARY_PATH}"
export MW_MCR_ROOT="\${MATLAB_ROOT}"

# --- Launch Server ---
echo "🚀 Launching MATLAB server (blocking)..."

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

LOG_FILE="logs/worker-${JOB_ID}.log"

echo "✅ Worker submitted successfully!"
echo "   Job ID:  ${JOB_ID}"
echo "   Log:     ~/logs/worker-${JOB_ID}.log"
echo "   Status:  Queued/Starting"

echo ""
echo "----------------------------------------------------------------"
echo "📡 Waiting for job to start and streaming log to local screen..."
echo "   (Press Ctrl+C to stop watching; the worker will continue running)"
echo "----------------------------------------------------------------"

# Wait for the log file to be created (max 60s)
MAX_RETRIES=20
COUNT=0
while ! ssh -q ${HPC_HOST} "[ -f ~/${LOG_FILE} ]"; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "⚠️  Log file not found yet. The job is likely still queued."
        echo "   You can check manually later: ssh ${HPC_HOST} 'tail -f ~/${LOG_FILE}'"
        exit 0
    fi
    echo "   ... waiting for log file creation (~/${LOG_FILE}) ..."
    sleep 3
    ((COUNT++))
done

echo "✅ Log found! Streaming output:"
echo "----------------------------------------------------------------"
ssh ${HPC_HOST} "tail -f ~/${LOG_FILE}"