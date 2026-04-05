# DiscoveryConnection: HPC Workflows for PetaKit5D

A collection of standardized scripts for launching interactive Jupyter sessions and batch processing jobs on the Discovery or Innovator HPC clusters.

---

## 🚀 Workflows

This repository supports four primary modes of operation:

1. **[Interactive Jupyter](#1-interactive-jupyter)**: Launch a persistent JupyterLab session on a compute node with automated SSH tunneling.
2. **[Interactive Jupyter + MATLAB Server](#2-interactive-jupyter--matlab-server)**: Same as above, but includes a persistent background MATLAB worker for PetaKit processing.
3. **[Batch PetaKit Processing](#3-batch-petakit-processing)**: Headless submission of large deskew/rotate datasets via Slurm.
4. **[OPM Job Submission](#4-opm-job-submission)**: Lightweight CLI to submit JSON job tickets for the OPM pipeline.

---

## 🛠️ Prerequisites

### Local Machine (macOS)

- **Terminal & tmux**: Requires `tmux` for background tunneling.
- **SSH Config**: You MUST have a host entry in `~/.ssh/config` named `Discovery` or `Innovator`.

  ```ssh
  Host Discovery
      HostName discovery.hpc.edu
      User your_username
  ```

### HPC Cluster

- **Environment**: A Python virtual environment (default: `~/ppk5d`) with `jupyterlab` and `PyPetaKit5D` installed.
- **Modules**: Access to `matlab` and `pypetakit5d` modules.
- **Paths**: Project code should reside in `~/software` on the cluster.

---

## 📖 How to Run

### 1. Interactive Jupyter

Launches JupyterLab on a compute node and opens it in your local browser.

```bash
# Start a session
./start_hpc_jupyter.sh -H Discovery -p compute -c 4

# Reconnect if the tunnel breaks
./reconnect_hpc_jupyter.sh

# Stop and clean up
./kill_hpc_jupyter.sh <JOB_ID>
```

### 2. Interactive Jupyter + MATLAB Server

Ideal for interactive PetaKit5D development requiring a background worker.

```bash
# Start Jupyter + Server
./start_hpc_jupyter_matlab.sh -p gpu -m 128 -g gpu:1

# Or start a standalone worker
./launch_petakit_worker.sh

# Stop a standalone worker
./kill_petakit_worker.sh <JOB_ID>
```

### 3. Batch PetaKit Processing

Submit large datasets for non-interactive processing.

```bash
./run_workflow.sh -d /path/to/hpc/dataset -H Discovery
```

*Note: This automatically transfers the necessary Python CLIs to your HPC home before submission.*

### 4. OPM Job Submission

Submit individual job tickets for the automated pipeline.

```bash
python submit_opm.py /path/to/data --angle 122.0 --psf /path/to/psf.tif
```

---

## ⚙️ Configuration & Customization

### Central Shared Logic (`hpc_common.sh`)

Common logic for port discovery, host validation, and tunnel management is factored into `hpc_common.sh`. Edit this file to add new clusters or change global default MATLAB paths.

### Python CLIs

Both `generate_config.py` and `process_job.py` are now parameterizable CLIs.

```bash
# Example: Custom config generation
python generate_config.py --max-cpus 64 --mem-per-cpu 8.0
```

### Slurm Tweaks

Resource requests (CPU, Mem, Time) can be passed as flags to the shell scripts:

- `-c, --cpus`
- `-m, --mem`
- `-t, --time`
- `-p, --partition`

---

## 📂 File Structure

| File | Purpose |
| :--- | :--- |
| `hpc_common.sh` | **[Shared]** Logic for tunnels, ports, and host config. |
| `start_hpc_jupyter.sh` | Interactive Jupyter launcher. |
| `start_hpc_jupyter_matlab.sh` | Jupyter + PetaKit Server launcher. |
| `reconnect_hpc_jupyter.sh` | Re-establishes broken SSH tunnels. |
| `kill_hpc_jupyter.sh` | Remote job and local tunnel cleanup. |
| `launch_petakit_worker.sh` | Headless MATLAB worker launcher. |
| `kill_petakit_worker.sh` | Stops standalone MATLAB workers. |
| `generate_config.py` | CLI for PyPetaKit5D cluster configuration. |
| `process_job.py` | CLI for dataset processing submission. |
| `run_workflow.sh` | Wrapper for batch job submission. |
| `submit_opm.py` | Ticket generator for OPM jobs. |

---

## 🧹 Maintenance

Always use `./kill_hpc_jupyter.sh` to stop your sessions. This ensures both the Slurm job on the HPC and the `tmux` session on your Mac are terminated, preventing orphaned processes.
