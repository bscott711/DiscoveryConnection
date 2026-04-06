#!/bin/bash

# Define the list of directories to copy
SOURCES=(
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/20251016_JD_PAK2KO_Rab5cNG_memScar/CS6/Cell_1"
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/202051016_JD_WT_Rab5cNG-memScar/CS5/Cell_1"
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_3/20251016_JD_WT_NODRUG_2xFYVEmScar_MemNG/CS2/Cell_1"
    )

# Loop through the array and copy each sequentially to the current directory (.)
for SRC in "${SOURCES[@]}"; do
    echo "Copying $SRC..."
    cp -r "$SRC" .
done
echo "All copies complete."