#!/bin/bash
# This (simple) script is designed to mass rename SAF generated directories into unique serial ids as provided by a mapping CSV spreadsheet.
# This script requires: bash, basename, grep, sed.
#
# This script is designed to operate on one directory at a time, so you should use a for loop to process an entire SAF set.
# Example:
#   ```
#   for i in * ; do ../rename_saf_directory.sh $i ../mapping.csv ; done
#   ```
#
# The SAF generated directories are named based on their row numbers in the input spreadsheet.
# The mapping file should have the same row structure as the input spreadsheet.
# Unlike the input spreadsheet, the mapping file needs only 3 columns and in this order: "Serial ID", "DOI", and "Title".
# The mapping file must be a UTF-8 encoded CSV.
#
# Note: The DOI and Title are used to help ensure that the mapping file is correct.
# The DOI is not expected to be unique (distinct) but the "Serial ID" is expected to be unique (distinct).
#
# Note: A row in the mapping file represents the mapping to a given "Serial ID" for a directory with the same row number.
# Make sure the rows in the mapping file start at 2 because the input CSV starts at row 2 (so add a row of column headers).
#
# Note: the "Title" may contain commas, and this script is not designed to parse commas inside of a quoted CSV file.
# To reduce the impact of this potential problem, the title is the last column and only used if the DOI match fails.
#
# Note: this is not designed to handle all possible characters in the name.
# As a result, when some titles have unusual characters that grep does not handle well, the detection will fail and the file will not be renamed.
# These have to be manually corrected.
#
# Note: there can be rename conflicts as a result of serial ids matching exist directory names.
# To avoid this, try renaming every directory to have something like 'xx-' in front of it before running the script.
# Adding the 'xx-' prefix would not change the order of the directories.

main() {
  local directory=$1
  local parent_directory=
  local mapping_file=$2
  local base=
  local new_name=
  local match=
  local matches=
  local result=
  local title=
  local doi=
  local serial_id=

  if [[ $directory == "" || ! -d "$directory" ]] ; then
    echo "ERROR: Invalid directory: '$directory'."
    return 1
  fi

  if [[ ! -f "$mapping_file" ]] ; then
    echo "ERROR: Invalid mapping file: '$mapping_file'."
    return 1
  fi

  base=$(basename $directory)
  parent_directory=$(echo $directory | sed -e "s|$base$||" -e "s|/*$||")
  if [[ $parent_directory != "" ]] ; then
    parent_directory="${parent_directory}/"
  fi

  if [[ ! -f "$directory/dublin_core.xml" ]] ; then
    echo "ERROR: Cannot Move: '$base' dublin_core.xml file not found."
    return 1
  fi

  # Use the DOI (or title) to attempt to validate a given row before renaming.
  match_against_doi_or_title

  #echo "Renaming using: '$match'"
  matches=$(grep ",$match," "$mapping_file" | wc -l)
  if [[ $matches != "1" ]] ; then
    echo "ERROR: Too many or too few matches for '$base': '$matches'."
    return 1
  fi

  serial_id=$(grep ",$match," "$mapping_file" | sed -e 's|,.*$||')
  if [[ $serial_id == "" ]] ; then
    echo "ERROR: Failed to map '$base' to the Serial ID."
    return 1
  fi

  new_name=$serial_id
  if [[ -d $new_name ]] ; then
    new_name=${new_name}.duplicate-$RANDOM
    echo "WARNING: Duplicate Serial ID detected, renaming to '$new_name."
  fi

  if [[ $new_name == "" ]] ; then
    echo "ERROR: Cannot Move: '$directory' No valid DC Identifier URI found."
    return 1
  fi

  mv -v "$directory" "$parent_directory$new_name"
  result=$?
  if [[ $result -ne 0 ]] ; then
    echo "ERROR: Failed to Move: '$directory' to '$parent_directory$new_name'."
    return $result
  fi

  return 0
}

match_against_doi_or_title() {
  doi=$(grep -o '<dcvalue element="relation" qualifier="uri" language="en">.*</dcvalue>' $directory/dublin_core.xml | sed -e 's|<dcvalue element="relation" qualifier="uri" language="en">||' -e 's|</dcvalue>||')
  if [[ $doi == "" ]] ; then
    title=$(grep -o '<dcvalue element="title" language="en">.*</dcvalue>' $directory/dublin_core.xml | sed -e 's|<dcvalue element="title" language="en">||' -e 's|</dcvalue>||')
    if [[ $title == "" ]] ; then
      echo "ERROR: Unable to find doi and title for: '$directory'."
      return 1
    fi
    match=$(echo $title | sed -e 's|\.|\\.|g')
  else
    match=$(echo $doi | sed -e 's|\.|\\.|g')
  fi
}

main "$1" "$2"
