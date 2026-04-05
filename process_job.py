import argparse
import os
import sys
import PyPetaKit5D as ppk  # type: ignore

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Submit a PetaKit5D deskew/rotate job via PyPetaKit5D."
    )
    p.add_argument("--dataset", required=True, nargs="+",
                   help="One or more dataset directories.")
    p.add_argument("--config-file", default=os.path.expanduser("~/pypetakit_config.json"))
    p.add_argument("--xy-pixel", type=float, default=0.108)
    p.add_argument("--dz", type=float, default=0.5)
    p.add_argument("--skew-angle", type=float, default=32.8)
    p.add_argument("--channels", nargs="+", default=["CamA", "CamB"])
    p.add_argument("--no-deskew", action="store_true")
    p.add_argument("--no-rotate", action="store_true")
    return p.parse_args()

def main() -> None:
    args = parse_args()

    # Expand user paths if necessary and get absolute paths
    data_paths = [os.path.abspath(os.path.expanduser(d)) for d in args.dataset]
    deskew = not args.no_deskew
    rotate = not args.no_rotate

    print(f"Submitting PetaKit5D job for {len(data_paths)} dataset(s):")
    for d in data_paths:
        print(" -", d)

    try:
        ppk.XR_deskew_rotate_data_wrapper(
            data_paths,
            deskew=deskew,
            rotate=rotate,
            DSRCombined=True,
            xyPixelSize=args.xy_pixel,
            dz=args.dz,
            skewAngle=args.skew_angle,
            objectiveScan=False,
            reverse=True,
            channelPatterns=args.channels,
            FFCorrection=False,
            lowerLimit=0.4,
            constOffset=1.0,
            FFImagePaths=[""],
            backgroundPaths=[""],
            largeFile=False,
            zarrFile=False,
            saveZarr=False,
            blockSize=[256, 256, 256],
            save16bit=True,
            parseCluster=True,
            masterCompute=False,
            configFile=args.config_file,
            mccMode=True,
            BKRemoval=False,
            save3DStack=True,
            saveMIP=True,
            interpMethod="linear",
        )
        print('Job submitted to cluster successfully!')
        print(f'Check progress with: squeue -u {os.getenv("USER", "your_user")}')
    except Exception as e:
        print(f"Error in script: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()