#!/bin/bash
 
main() {
    local batch_size=$1
    local item_directories=
    local batch_directory=
    local item_directory=
    local directory=
    local return_code=0
    local item_directory_counter=0
    local batch_counter=0
 
    if [[ $batch_size == "" ]] ; then
        echo "Usage:  make_batches batch_size"
        return 0;
    fi


 
    # For each item_directory in BASE_DIR.
    item_directories=$(find . -type d -maxdepth 1)
    for item_directory in $item_directories ; do

        ((item_directory_counter++))

        echo "processing item directory $item_directory ($item_directory_counter of $batch_size)"

        # Build the batch directory if we're just on a new batch
        if [[ $item_directory_counter -eq 1 ]] ; then
            ((batch_counter++))
            batch_directory="batch_${batch_counter}"
            echo "First item in batch $batch_counter.  Attempting to create new dir $batch_directory"
            # Test if the directory exists.
            if [[ ! -d $batch_directory ]] ; then
                echo "Creating batch directory $batch_directory"
                mkdir $batch_directory
                return_code=$?
            fi
        fi

        # move the item_directory into the current batch directory ...
        if [[ $return_code -eq 0 ]] ; then
            echo "Moving $item_directory to $batch_directory/$item_directory"
            mv $item_directory $batch_directory/$item_directory
            return_code=$?
        fi
 
        if [[ $return_code -ne 0 ]] ; then
          echo "Operation Failed for item_directory '$item_directory', return code: $return_code"
        fi

        #if we have come now to the full batch size, restart our item
        #counter, as we will need to make a new directory for the new batch
        if [[ $item_directory_counter -eq $batch_size ]] ; then
            item_directory_counter=0
        fi

    done
 
    return $return_code
}
 
main $*