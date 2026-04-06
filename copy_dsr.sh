#!/bin/bash

# The original mmfs1 directories for all four datasets
ORIG_DESTINATIONS=(
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/20251016_JD_PAK2KO_Rab5cNG_memScar/CS5/Cell_1"
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/20251016_JD_PAK2KO_Rab5cNG_memScar/CS6/Cell_1"
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_3/20251016_JD_WT_NODRUG_2xFYVEmScar_MemNG/CS2/Cell_1"
    # ADDED: The WT + Rab5c dataset (with the original mmfs1 typo)
    "/mmfs1/scratch/jacks.local/microscopy/OPM_RAW/20251016_JD_BMDM_2/202051016_JD_WT_Rab5cNG-memScar/CS5/Cell_1"
    
)

UPLOAD_BASE="/mmfs2/scratch/SDSMT.LOCAL/bscott/DataUpload"
NEW_BASE="/mmfs1/scratch/jacks.local/microscopy/OPM_preprocessed"

# Enable nullglob so unmatched wildcards safely return empty arrays
shopt -s nullglob

# Ensure the new base directory exists
mkdir -p "$NEW_BASE"

for ORIG_DEST in "${ORIG_DESTINATIONS[@]}"; do
    # Extract the last 3 components of the path
    SUBPATH=$(echo "$ORIG_DEST" | awk -F/ '{print $(NF-2)"/"$(NF-1)"/"$NF}')
    
    # CHANGE: Fix the mmfs1 typo (202051016 -> 20251016) so it matches the mmfs2 directory
    UPLOAD_SUBPATH="${SUBPATH/202051016/20251016}"
    
    # Determine the new destination path by replacing OPM_RAW with OPM_preprocessed
    NEW_DEST="${ORIG_DEST/OPM_RAW/OPM_preprocessed}"
    
    # Find the DSR directory using a wildcard for the MMStack_Pos folder
    DSR_DIRS=( "$UPLOAD_BASE"/"$UPLOAD_SUBPATH"/*/DSR )

    if [ ${#DSR_DIRS[@]} -eq 0 ]; then
        echo "WARNING: DSR directory not found for $UPLOAD_SUBPATH"
        continue
    fi

    # Create the new destination directory tree
    mkdir -p "$NEW_DEST"

    # Loop through found DSR directories and execute the copy
    for SRC_DSR in "${DSR_DIRS[@]}"; do
        # Check if DSR already exists in the destination before copying
        if [ -d "$NEW_DEST/DSR" ]; then
            echo "Skipping: DSR already exists in $NEW_DEST/"
        else
            echo "Copying DSR from: $SRC_DSR"
            echo "              To: $NEW_DEST/"
            cp -r "$SRC_DSR" "$NEW_DEST/"
        fi
    done
done

# Recursively ensure group read, write, and execute (traverse) permissions on the new folder
chmod -R g+rwX "$NEW_BASE"

echo "All copies complete."