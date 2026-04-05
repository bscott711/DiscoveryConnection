import argparse
import os
import PyPetaKit5D as ppk  # type: ignore

def main():
    parser = argparse.ArgumentParser(
        description="Generate PyPetaKit5D cluster config JSON."
    )
    parser.add_argument(
        "--output",
        default=os.path.expanduser("~/pypetakit_config.json"),
        help="Path to write config JSON (default: ~/pypetakit_config.json)",
    )
    parser.add_argument(
        "--mcr-root",
        default="/cm/shared/apps_local/matlab/R2024B",
        help="MATLAB MCR root on the cluster.",
    )
    parser.add_argument(
        "--mcc-master-script",
        default="/mmfs2/cm/shared/apps_local/petakit5d/mcc/linux/run_mccMaster.sh",
        help="Path to run_mccMaster.sh on the cluster.",
    )
    parser.add_argument("--mem-per-cpu", type=float, default=5.0)
    parser.add_argument("--job-time-limit", type=int, default=48)
    parser.add_argument("--max-cpus", type=int, default=48)

    args = parser.parse_args()

    print(f"Generating config at {args.output} for MCR={args.mcr_root}")
    ppk.generate_config_file(
        args.output,
        MCCMasterStr=args.mcc_master_script,
        MCRParam=args.mcr_root,
        memPerCPU=args.mem_per_cpu,
        jobTimeLimit=args.job_time_limit,
        maxCPUNum=args.max_cpus,
        GNUparallel=True,
        masterCompute=True,
        parseCluster=False,
        SlurmParam="",
    )
    print(f"✅ Config saved to {args.output}")

if __name__ == "__main__":
    main()