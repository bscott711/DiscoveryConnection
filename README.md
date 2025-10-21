# Interactive JupyterLab on the HPC with Automated Tunneling

This guide provides a robust, user-friendly workflow for launching a persistent JupyterLab session on a GPU compute node. The process is fully automated: it submits a Slurm job, creates an SSH tunnel, and opens your browser—all in one step

---

## Overview

Instead of manually managing `tmux` sessions and tunnels, use the provided scripts to:

- ✅ Start JupyterLab on a GPU node via Slurm
- 🔒 Automatically create an SSH tunnel from your Mac to the compute node
- 🌐 Open JupyterLab in your default browser
- 🧹 Cleanly shut down both remote and local components when done

No need to keep a terminal open—everything runs in the background until you're ready to stop.

---

## Step 1: Start Your Session

Run the launch script from your **local machine (Mac)**:

```bash
./start_hpc_jupyter.sh
```

This script will:

1. Submit a Slurm job to start JupyterLab on a GPU node
2. Wait for the server to initialize
3. Automatically create an SSH tunnel using `tmux`
4. Open JupyterLab in your default web browser

💡 You’ll see output like:

```bash
🚀 Submitting JupyterLab job to the HPC...
✅ Job submitted with ID: 940
✅ Your server is ready!
🚀 Opening JupyterLab in your default browser...
```

A new Terminal window will open and run the tunnel in the background. You can safely close the original terminal.

---

## Step 2: Stop Your Session

When finished, clean up both ends with one command:

```bash
./kill_hpc_jupyter.sh <JOB_ID>
```

Replace `<JOB_ID>` with the number from the startup message (e.g., `940`).

Example:

```bash
./kill_hpc_jupyter.sh 940
```

This script will:

1. Cancel the Slurm job on the HPC
2. Terminate the local `tmux` SSH tunnel session
3. Print confirmation when cleanup is complete

> ⚠️ Always use this script to avoid leaving orphaned jobs or tunnels running.

---

## How It Works

| Component | Purpose |
|---------|--------|
| `start_hpc_jupyter.sh` | Launches JupyterLab via Slurm and sets up secure tunneling |
| `kill_hpc_jupyter.sh` | Safely stops the job and closes the tunnel |
| Slurm (`sbatch`) | Runs JupyterLab on a dedicated GPU node |
| SSH `-L` + `-J` | Creates encrypted port forwarding through the login node |
| `tmux` | Keeps the tunnel alive even if network drops |

---

## Requirements

- macOS with `Terminal.app` and `osascript` (built-in)
- Access to the HPC cluster via SSH (configured as `Discovery`)
- A Python virtual environment (e.g., `~/ppk5d`) with JupyterLab installed
- MATLAB R2024b module available on the cluster

---

## Notes

- The tunnel uses a random high-numbered port on the compute node and forwards it to `localhost:9999` on your Mac.
- If the browser doesn’t open automatically, copy the URL printed in the log file and change the port to `9999`.
- These scripts are designed for ease of use and resilience—ideal for daily interactive computing.

---
