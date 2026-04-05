#!/bin/bash
# hpc_common.sh - Shared logic for DiscoveryConnection scripts.
#
# This file is meant to be sourced by other scripts:
#   source "$(dirname "$0")/hpc_common.sh"

# --- Host Validation ---
validate_host() {
    local host=$1
    case "$host" in
        Discovery|Innovator)
            return 0
            ;;
        *)
            echo "❌ Error: Invalid host '$host'."
            echo "Please use 'Discovery' or 'Innovator'."
            return 1
            ;;
    esac
}

# --- MATLAB Configuration ---
# Returns the MATLAB root and module based on the host.
get_matlab_config() {
    local host=$1
    if [[ "$host" == "Discovery" ]]; then
        echo "matlab/R2024b:/cm/shared/apps_local/matlab/R2024B"
    elif [[ "$host" == "Innovator" ]]; then
        echo "matlab/R2023b:/cm/shared/apps_local/matlab/R2023B"
    fi
}

# --- Port Finding ---
find_available_port() {
    local base_port=$1
    local max_attempts=50
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local port_to_check
        if [ $attempt -eq 0 ]; then
            port_to_check=$base_port
        else
            # For subsequent attempts, use random ports in range
            port_to_check=$((8000 + RANDOM % 2000))
        fi
        
        # Check if port is available locally (macOS specific check)
        if ! lsof -Pi :$port_to_check -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo $port_to_check
            return 0
        fi
        attempt=$((attempt + 1))
    done
    
    echo "❌ Error: Could not find an available local port after $max_attempts attempts" >&2
    return 1
}

# --- Tunnel Management ---
start_tmux_tunnel() {
    local session_name=$1
    local hpc_host=$2
    local node=$3
    local local_port=$4
    local remote_port=$5
    
    local ssh_command="ssh -N -o StrictHostKeyChecking=no -L ${local_port}:localhost:${remote_port} -J ${hpc_host} ${node}"
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "❌ Error: tunnel setup currently requires macOS (osascript)." >&2
        return 1
    fi

    # Kill old session if it exists
    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux kill-session -t "$session_name"
    fi

    osascript <<EOF
tell application "Terminal"
    activate
    do script "tmux new -s ${session_name} '${ssh_command}'"
end tell
EOF
    return 0
}

# --- Remote Environment Helpers ---
# Generates the shell code to set up MATLAB paths on the cluster node.
get_matlab_env_setup() {
    local matlab_root=$1
    cat <<EOF
echo "✅ [sbatch] Setting MATLAB environment variables..."
export LD_LIBRARY_PATH="${matlab_root}/runtime/glnxa64:${matlab_root}/bin/glnxa64:${matlab_root}/sys/os/glnxa64:${matlab_root}/sys/opengl/lib/glnxa64:\${LD_LIBRARY_PATH}"
export MW_MCR_ROOT="${matlab_root}"
EOF
}
