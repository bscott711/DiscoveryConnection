import PyPetaKit5D as ppk # type: ignore
import os
import sys

def main():
    """
    Main function to configure and run the PetaKit5D processing job.
    """
    try:
        # --- 1. SET YOUR DATASET PARAMETERS ---
        dataset_path = '/mmfs2/scratch/SDSMT.LOCAL/bscott/DataUpload/20200218_NDN-antiBiotin_CS2/CS2/cell1/'
        # Note: This is a Python list, not a MATLAB cell array
        dataPath_exps = [dataset_path]
        
        # --- 2. SET INSTRUMENT PARAMETERS ---
        xyPixelSize = 0.108
        dz = 0.5
        skewAngle = 32.8
        channelPatterns = ['CamA', 'CamB'] # Python list
        objectiveScan = False
        reverse = True
        
        # --- 3. SET CLUSTER & MCC PARAMETERS ---
        parseCluster = True   # Use the Slurm cluster
        masterCompute = False # Do not run on the master node
        
        # Full path to the config file
        configFile = '/home/SDSMT.LOCAL/bscott/pypetakit_config.json'
        # This is still true, as PyPetaKit5D calls the compiled MATLAB code
        mccMode = True        

        # --- 4. OTHER PROCESSING PARAMETERS ---
        # Note: Using Python boolean "True" and "False"
        deskew = True
        rotate = True
        DSRCombined = True
        FFCorrection = False
        BKRemoval = False
        lowerLimit = 0.4
        constOffset = 1.0
        FFImagePaths = [''] # Python list
        backgroundPaths = [''] # Python list
        largeFile = False
        zarrFile = False
        saveZarr = False
        blockSize = [256, 256, 256]
        save16bit = True
        save3DStack = True
        saveMIP = True
        interpMethod = 'linear'
        
        # --- 5. RUN THE SUBMISSION ---
        print(f'Submitting job to cluster for: {dataset_path}')

        # Call the Python wrapper function using keyword arguments
        ppk.XR_deskew_rotate_data_wrapper(
            dataPath_exps,
            deskew=deskew, rotate=rotate,
            DSRCombined=DSRCombined, xyPixelSize=xyPixelSize, dz=dz, skewAngle=skewAngle,
            objectiveScan=objectiveScan, reverse=reverse, channelPatterns=channelPatterns,
            FFCorrection=FFCorrection, lowerLimit=lowerLimit, constOffset=constOffset,
            FFImagePaths=FFImagePaths, backgroundPaths=backgroundPaths, largeFile=largeFile,
            zarrFile=zarrFile, saveZarr=saveZarr, blockSize=blockSize, save16bit=save16bit,
            parseCluster=parseCluster, masterCompute=masterCompute, configFile=configFile,
            mccMode=mccMode, BKRemoval=BKRemoval, save3DStack=save3DStack,
            saveMIP=saveMIP, interpMethod=interpMethod
        )

        print('Job submitted to cluster successfully!')
        print(f'Check progress with: squeue -u {os.getenv("USER")}')

    except Exception as e:
        print(f'Error in script: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()