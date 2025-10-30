import os
import PyPetaKit5D as ppk # type: ignore

# --- Configuration ---
home_dir = "/home/SDSMT.LOCAL/bscott"
config_file_path = os.path.join(home_dir, "pypetakit_config.json")
mcr_root = "/cm/shared/apps_local/matlab/R2024B"
mcc_master_script = "/mmfs2/cm/shared/apps_local/petakit5d/mcc/linux/run_mccMaster.sh"

print("--- This is the LOCAL config generator ---")
print(f"It will create {config_file_path} on the HPC.")

ppk.generate_config_file(
    config_file_path,
    MCCMasterStr=mcc_master_script,
    MCRParam=mcr_root,
    memPerCPU=5.0,      # Adjusted: ~5GB per CPU (240GB total)
    jobTimeLimit=48,
    maxCPUNum=48,       # <-- Request 48 CPU cores
    GNUparallel=True,
    masterCompute=True, # Run locally on the allocated node
    parseCluster=False, # Do NOT submit sub-jobs
    SlurmParam=""
)

print(f"✅ Config saved to {config_file_path}")