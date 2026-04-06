#!/bin/bash

SOURCES=(
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/20251016_JD_PAK2KO_Rab5cNG_memScar/CS5/Cell_1"
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/20251016_JD_PAK2KO_Rab5cNG_memScar/CS6/Cell_1"
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/202051016_JD_WT_Rab5cNG-memScar/CS5/Cell_1"
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_3/20251016_JD_WT_NODRUG_2xFYVEmScar_MemNG/CS2/Cell_1"
)

UPLOAD_BASE="/mmfs2/scratch/SDSMT.LOCAL/bscott/DataUpload"

shopt -s nullglob

for SRC in "${SOURCES[@]}"; do
    # Extract the Condition/CS#/Cell_1 structure
    SUBPATH=$(echo "$SRC" | awk -F/ '{print $(NF-2)"/"$(NF-1)"/"$NF}')
    UPLOAD_DIR="$UPLOAD_BASE/$SUBPATH"
    
    echo "Checking: $SUBPATH"
    
    if [ -d "$UPLOAD_DIR" ]; then
        echo "  [OK] Base directory found in mmfs2."
        
        # Look for the DSR directory inside any MMStack_Pos folder
        DSR_DIRS=( "$UPLOAD_DIR"/*/DSR )
        
        if [ ${#DSR_DIRS[@]} -gt 0 ]; then
            for DSR in "${DSR_DIRS[@]}"; do
                echo "  [OK] DSR found: $DSR"
            done
        else
            echo "  [X]  DSR directory MISSING."
        fi
    else
        echo "  [X]  Base directory MISSING from mmfs2."
    fi
    echo "--------------------------------------------------"
done