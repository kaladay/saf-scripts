#!/bin/bash
#
# This (simple) script is designed to mass rename SAF generated directories into unique serial ids as provided by a mapping CSV spreadsheet.
#
# This script is designed to operate on multiple top-level sub-directories within a single source directory.
#
# The SAF generated directories are named based on their row numbers in the input spreadsheet.
# The mapping file should have the same row structure as the input spreadsheet.
# Unlike the input spreadsheet, the mapping file needs only a few columns: "Serial ID", "DOI", "Title", and "Journal Title".
# This set of columns may be configured.
# The mapping file must be a UTF-8 encoded CSV.
#
# The DOI and Title are used to help ensure that the mapping file is correct.
#
# A row in the mapping file represents the mapping to a given "Serial ID" for a directory with the same row number.
# Make sure the rows in the mapping file start at 2 because the input CSV starts at row 2 (so add a row of column headers).
#
# The "Title" may contain commas, and this script is not designed to parse commas inside of a quoted CSV file.
# To reduce the impact of this potential problem, the title could be set to the last column and only used if the DOI match fails.
#
# This script is not designed to handle all possible characters in the name.
# As a result, when some titles have unusual characters that grep does not handle well, the detection will fail and the file will not be renamed.
# These have to be manually corrected.
#
# There can be rename conflicts as a result of serial ids matching exist directory names.
# To avoid this, try prepending something like 'xx-' to every top-level sub-directory before running the script.
# Adding the 'xx-' prefix would not change the order of the directories.
#
# This expects a bash of at least version 4, but provides some limited work-arounds for known problems with bash version 3.
#
# Example Usage:
#   ```
#   dspace-saf-rename_directory.sh -m mapping.csv source_directory
#   ```
#
# depends on the following userspace commands:
#   bash, basename, date (optional), find, grep, sed, sort (optional), touch (optional), and wc.

main() {
    # standard main parameters
    local script_pathname=$0
    local get_help=
    local no_color=
    local grab_next=
    local parameter=
    local -i parameters_total=$#
    local extra_parameters=
    local -i extra_parameters_total=0
    local -i output_mode=0
    local -i legacy=0

    # generic
    local -i i=0
    local -i j=0

    # additional parameters
    local start_stamp=
    local source_directory=
    local -a columns=("Serial ID" "DOI" "Title" "Journal Title")
    local column_names=
    local file_map=
    local -i parse_doi=0
    local -i parse_title=0
    local -i is_last_doi=0
    local -i is_last_title=0
    local process_action="rename"

    # logging
    local log_file="changes.log"

    # commands
    local find_command="find"
    local grep_command="grep"
    local sort_command="sort"

    if [[ $(type -p date) ]] ; then
        log_file="changes-$(date +'%Y_%m_%d').log"

        start_stamp=$(date +'%Y/%m/%d %_I:%M:%S %P %z')
    fi

    # @todo: add support for awk.
    #if [[ $(type -p awk) ]] ; then
    #    grep_command="awk"
    #elif [[ $(type -p grep) ]] ; then
    #    grep_command="grep"
    #fi

    # reset, title, error, warning, highligh, notice, important.
    local c_r="\\033[0m"
    local c_t="\\033[1;33m"
    local c_e="\\033[1;31m"
    local c_w="\\033[0;33m"
    local c_h="\\033[1;49;36m"
    local c_n="\\033[0;01m"
    local c_i="\\033[0;49;36m"

    if [[ $parameters_total -gt 0 ]] ; then
        while [[ $i -lt $parameters_total ]] ; do
            let i++
            parameter="${!i}"

            if [[ $grab_next == "" ]] ; then
                if [[ $parameter == "-c" || $parameter == "--columns" ]] ; then
                    grab_next="$parameter"
                elif [[ $parameter == "-h" || $parameter == "--help" ]] ; then
                    let get_help=1
                elif [[ $parameter == "--legacy" ]] ; then
                    let legacy=1
                elif [[ $parameter == "-m" || $parameter == "--map" ]] ; then
                    grab_next="$parameter"
                elif [[ $parameter == "-n" || $parameter == "--no_color" ]] ; then
                    c_r=""
                    c_t=""
                    c_e=""
                    c_w=""
                    c_h=""
                    c_n=""
                    c_i=""
                elif [[ $parameter == "-P" || $parameter == "--progress" ]] ; then
                    if [[ $output_mode -eq 0 ]] ; then
                        let output_mode=2
                    elif [[ $output_mode -eq 1 ]] ; then
                        let output_mode=3
                    fi
                elif [[ $parameter == "-s" || $parameter == "--silent" ]] ; then
                    if [[ $output_mode -eq 0 ]] ; then
                        let output_mode=1
                    elif [[ $output_mode -eq 2 ]] ; then
                        let output_mode=3
                    fi
                elif [[ $parameter == "-V" || $parameter == "--validate" ]] ; then
                    process_action="validate"
                elif [[ $source_directory == "" ]] ; then
                    source_directory="$parameter"
                else
                    extra_parameters[${extra_parameters_total}]="$parameter"
                    let extra_parameters_total++
                fi
            else
                if [[ $grab_next == "-c" || $grab_next == "--columns" ]] ; then
                    column_names=$(echo "$parameter" | sed -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||' -e 's|,[[:space:]]*,*|,|g')

                    if [[ $column_names == "" ]] ; then
                        echo_out2
                        echo_warn "Ignoring column_names parameter and using default because there must be at least one column name."
                    fi

                    grab_next=
                elif [[ $grab_next == "-m" || $grab_next == "--map" ]] ; then
                    file_map=$(echo "$parameter" | sed -e 's|//*|/|g')
                    grab_next=
                else
                    break
                fi
            fi
        done
    fi

    if [[ $get_help -eq 1 || $i -eq 0 ]] ; then
        if [[ $output_mode -ne 0 && $output_mode -ne 3 ]] ; then
            let output_mode=0
            echo_out2
            echo_warn "Output is not suppressed when help is to be displayed."
        fi

        print_help
        return 0
    fi

    if [[ $grab_next != "" ]] ; then
        echo_out2
        echo_error "missing parameter for '$c_n$grab_next$c_e'"
        echo_out2
        return 1
    fi

    if [[ $extra_parameters_total -gt 0 ]] ; then
        let i=0
        echo_out2
        local custom_message="only one source directory may be specified at a time, you specified '$c_n$source_directory$c_e'"
        while [[ $i -lt $extra_parameters_total ]] ; do
            parameter=${extra_parameters[i]}
            custom_message="$custom_message, '$c_n$parameter$c_e'"
            let i++
        done
        echo_error "$custom_message."
        echo_out2
        return 1
    fi

    if [[ $(type -p basename) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (basename) command '${c_n}basename$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p $find_command) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (find) command '$c_n$find_command$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p grep) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (grep) command '${c_n}grep$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p sed) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (sed) command '${c_n}sed$c_r'"
        echo_out2
        return 1
    fi

    # if "sort" is not available, disable it.
    if [[ $(type -p $sort_command) == "" ]] ; then
        sort_command=
    fi

    if [[ $(type -p wc) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (wc) command '${c_n}wc$c_r'"
        echo_out2
        return 1
    fi

    if [[ $file_map == "" ]] ; then
        echo_out2
        echo_error "No map file specified, please use -m or --map to specify the map file."
        echo_out2
        return 1
    fi

    if [[ -d $file_map ]] ; then
        echo_out2
        echo_error "The map file cannot be a directory '$c_n$file_map$c_e'."
        echo_out2
        return 1
    fi

    if [[ ! -r $file_map ]] ; then
        echo_out2
        echo_error "The map file '$c_n$file_map$c_e' is not found or is not readable."
        echo_out2
        return 1
    fi

    if [[ ! -f $file_map ]] ; then
        echo_out2
        echo_error "The map file is not a valid file '$c_n$file_map$c_e'."
        echo_out2
        return 1
    fi

    if [[ $column_names != "" ]] ; then
        unset columns
        local -a columns=()

        IFS=',' read -r -a columns <<< "$column_names"

        # sanitize the individual column names.
        let i=0
        let j=1
        while [[ $i -lt ${#columns[@]} ]] ; do
            columns[$i]=$(echo "${columns[$i]}" | sed -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||')

            if [[ ${columns[$i]} == "DOI" ]] ; then
                let parse_doi=1

                if [[ $j -eq ${#columns[@]} ]] ; then
                    let is_last_doi=1
                fi
            elif [[ ${columns[$i]} == "Title" ]] ; then
                let parse_title=1

                if [[ $j -eq ${#columns[@]} ]] ; then
                    let is_last_title=1
                fi
            fi

            let i++
            let j++
        done
    else
        let i=0
        let j=1
        while [[ $i -lt ${#columns[@]} ]] ; do
            if [[ ${columns[$i]} == "DOI" ]] ; then
                let parse_doi=1

                if [[ $j -eq ${#columns[@]} ]] ; then
                    let is_last_doi=1
                fi
            elif [[ ${columns[$i]} == "Title" ]] ; then
                let parse_title=1

                if [[ $j -eq ${#columns[@]} ]] ; then
                    let is_last_title=1
                fi
            fi

            let i++
            let j++
        done
    fi

    if [[ ! -r $source_directory ]] ; then
        echo_out2
        echo_error "The source directory '$c_n$source_directory$c_e' is not found or not readable."
        echo_out2
        return 1
    fi

    if [[ ! -d $source_directory ]] ; then
        echo_out2
        echo_error "The source directory '$c_n$source_directory$c_e' is not a valid directory."
        echo_out2
        return 1
    fi

    if [[ ! -x $source_directory ]] ; then
        echo_out2
        echo_error "The source directory '$c_n$source_directory$c_e' is not executable."
        echo_out2
        return 1
    fi

    if [[ -d $log_file ]] ; then
        echo_out2
        echo_error "The log file cannot be a directory '$c_n$log_file$c_e'."
        echo_out2
        return 1
    fi

    if [[ $(type -p touch) != "" ]] ; then
        touch -f $log_file
        if [[ $? -ne 0 ]] ; then
            echo_out2
            echo_error "Unable to write to log file '$c_n$log_file$c_e'."
            echo_out2
            return 1
        fi
    fi

    process_content
    return $?
}

process_content() {
    local -i failure=0
    local -i i=0
    local -i row=0
    local -i total=0
    local index=
    local directory=
    local directory_name=
    local -a directories=()
    local -i directories_total=0
    local result_wc=
    local serial_id=
    local serial_id_from_parse=
    local matches=
    local matched_row=
    local -i match_is_quoted=0
    local doi_from_parse=
    local title_from_parse=
    local new_name=

    if [[ $process_action == "validate" ]] ; then
        echo_out
        echo_out_e "${c_t}Now Validating Map File:$c_r '$c_n$file_map$c_t'$c_r"

        log_out
        if [[ $start_stamp == "" ]] ; then
            log_out "===== Validating Map File: '$file_map' ====="
        else
            echo_out "Started On: $start_stamp" 2
            log_out "===== Validating Map File: '$file_map' ($start_stamp) ====="
        fi
    else
        echo_out
        echo_out_e "${c_t}Now Processing Map File:$c_r '$c_n$file_map$c_t'$c_r"

        log_out
        if [[ $start_stamp == "" ]] ; then
            log_out "===== Processing Map File: '$file_map' ====="
        else
            echo_out "Started On: $start_stamp" 2
            log_out "===== Processing Map File: '$file_map' ($start_stamp) ====="
        fi
    fi

    # build a list of directories within the specified source directory to process.
    if [[ $sort_command == "" ]] ; then
        for index in $($find_command $source_directory -nowarn -mindepth 1 -maxdepth 1 -type d ! -name '\.*') ; do
            directories["$directories_total"]=$(basename $index)
            let directories_total++
        done
    else
        for index in $($find_command $source_directory -nowarn -mindepth 1 -maxdepth 1 -type d ! -name '\.*' | sort -V) ; do
            directories["$directories_total"]=$(basename $index)
            let directories_total++
        done
    fi

    if [[ $directories_total -eq 0 ]] ; then
        echo_out2
        echo_warn "Did not find any sub-directories inside the source directory '$c_n$source_directory$c_w'." 2
        echo_out2
        log_warn "Did not find any sub-directories inside the source directory '$c_n$source_directory$c_w'." 2
        return 0
    fi

    result_wc=$(wc -l $file_map)
    if [[ $? -ne 0 ]] ; then
        echo_out2
        echo_error "Failed to get total lines of map file: '$c_n$file_map$c_e'."
        echo_out2
        log_error "Failed to get total lines of map file: '$file_map'."
        return 1
    fi

    let total=$(echo $result_wc | grep -so "^[[:digit:]][[:digit:]]*")
    if [[ $total -lt 2 ]] ; then
        echo_out2
        echo_error "Mapping file has to few rows, must have at least 2 rows: '$c_n$file_map$c_e'."
        echo_out2
        log_error "Mapping file has to few rows, must have at least 2 rows: '$file_map'."
        return 1
    fi

    let i=0
    while [[ $i < ${#directories[@]} ]] ; do
        directory=${directories[$i]}
        directory_name=$(basename $directory)

        echo_out
        echo_out_e "${c_t}Now Processing Directory:$c_r $c_n$directory_name$c_r"

        log_out
        log_out "==== Processing Directory: '$directory_name' ===="

        echo_out_e "Validating against the map file." 2
        log_out "Validating directory '$directory' against the map file." 2

        if [[ $(echo ${directories[$i]} | grep -so "^[[:digit:]]*$") == "" ]] ; then
            if [[ $(echo ${directories[$i]} | grep -so "^[[:digit:]][[:digit:]]*\.duplicate-[[:digit:]][[:digit:]]*$") == "" ]] ; then
                echo_warn "Invalid Directory Name: '$c_n$directory_name$c_w', must be a number, skipping directory." 4
                echo_out2
                log_warn "Invalid Directory Name: '$directory_name', must be a number." 4
            else
                echo_warn "Skipping Duplicate Directory: '$c_n$directory_name$c_w'." 4
                echo_out2
                log_warn "Skipping Duplicate Directory: '$directory_name'." 4
            fi

            let i++
            continue
        else
            let row=${directories[$i]}
        fi

        if [[ $directory_name != $row ]] ; then
            echo_warn "Invalid Directory Name: '$c_n$directory_name$c_w', must be a number, skipping directory." 4
            echo_out2
            log_warn "Invalid Directory Name: '$directory_name', must be a number." 4

            let i++
            continue
        fi

        if [[ $row -lt 2 ]] ; then
            echo_warn "Invalid Directory Name: '$c_n$directory_name$c_w', row number must be greater than 1, skipping directory." 4
            echo_out2
            log_warn "Invalid Directory Name: '$directory_name', row number must be greater than 1." 4

            let i++
            continue
        fi

        if [[ $row -gt $total ]] ; then
            echo_warn "Invalid Directory Name: '$c_n$directory_name$c_w', row number must be less than number of rows in map file, skipping directory." 4
            echo_out2
            log_warn "Invalid Directory Name: '$directory_name', row number must be less than number of rows in map file." 4

            let i++
            continue
        fi

        # Validate that the given row has a non-empty first column (the unique id), that it is a valid number, and confirm that it is unique within the map file.
        matched_row=$(sed "$row,$row!d" $file_map)
        if [[ $? -ne 0 || $matched_row == "" ]] ; then
            echo_error "Failed to parse row '$c_n$row$c_e' using sed command." 4
            echo_out2
            log_error "Failed to parse row '$row' using sed command." 4
            failure=1

            let i++
            continue
        fi

        if [[ ${#columns[@]} -eq 1 ]] ; then
            serial_id=$(echo $matched_row | grep -so "^[^,]*\$")
        else
            serial_id=$(echo $matched_row | grep -so "^[^,]*," | sed -e 's|,$||')
        fi

        if [[ $? -ne 0 || $serial_id == "" ]] ; then
            echo_error "Failed to parse Serial ID from row '$c_n$row$c_e' in the map file, matched row: '$c_n$matched_row$c_e'." 4
            echo_out2
            log_error "Failed to parse Serial ID from row '$row' in the map file, matched row: '$matched_row'." 4

            let i++
            continue
        fi

        if [[ ${#columns[@]} -eq 1 ]] ; then
            matches=$(grep -s "^$serial_id\$" "$file_map" | wc -l)
        else
            matches=$(grep -s "^$serial_id," "$file_map" | wc -l)
        fi

        if [[ $matches != "1" ]] ; then
            echo_error "Too many matches for '$c_n$serial_id_number$c_e': '$c_n$matches$c_e'." 4
            echo_out2
            log_error "Too many matches for '$serial_id_number': '$matches'." 4

            let i++
            continue
        fi

        # The serial ID is derived from the row number, search for the DOI or Title (if applicable) and get the Serial ID for that row.
        # The serial ID by row and serial ID by DOI or Title match should be the same.
        parse_doi_or_title
        if [[ $? -eq 1 ]] ; then
            failure=1
            let i++
            continue
        fi

        if [[ $doi_from_parse != "" || $title_from_parse != "" ]] ; then
            serial_id_from_parse=
            let match_is_quoted=0

            if [[ $doi_from_parse != "" ]] ; then
                echo_out_e "Parsing Serial ID from map using '${c_n}DOI$c_r': '$c_n$doi_from_parse$c_r'." 2
                log_out "Parsing Serial ID from map using 'DOI': '$doi_from_parse'." 2

                if [[ $is_last_doi -eq 0 ]] ; then
                    matches=$(grep -s ",$doi_from_parse," "$file_map" | wc -l)
                else
                    matches=$(grep -s ",$doi_from_parse\$" "$file_map" | wc -l)
                fi

                if [[ $matches == "0" ]] ; then
                    if [[ $is_last_doi -eq 0 ]] ; then
                        matches=$(grep -s ",\"$doi_from_parse\"," "$file_map" | wc -l)
                    else
                        matches=$(grep -s ",\"$doi_from_parse\"\$" "$file_map" | wc -l)
                    fi

                    if [[ $matches == "1" ]] ; then
                        let match_is_quoted=1
                    fi
                fi

                if [[ $matches != "1" ]] ; then
                    echo_error "Too many or too few matches for '$c_n$directory_name$c_e', using DOI '$c_n$doi_from_parse$c_e'." 4
                    echo_out2
                    log_error "Too many or too few matches for '$directory_name', using DOI '$doi_from_parse'." 4

                    failure=1
                    let i++
                    continue
                fi

                if [[ $is_last_doi -eq 0 ]] ; then
                    serial_id_from_parse=$(grep -s ",$doi_from_parse," "$file_map" | sed -e 's|,.*$||')
                else
                    serial_id_from_parse=$(grep -s ",$doi_from_parse\$" "$file_map" | sed -e 's|,.*$||')
                fi

                if [[ $serial_id_from_parse == "" ]] ; then
                    echo_error "Failed to load Serial ID for '$c_n$directory_name$c_e', using DOI '$c_n$doi_from_parse$c_e'." 4
                    echo_out2
                    log_error "Failed to load Serial ID for '$directory_name', using DOI '$doi_from_parse'." 4

                    failure=1
                    let i++
                    continue
                fi
            elif [[ $title_from_parse != "" ]] ; then
                echo_out_e "Parsing Serial ID from map using '${c_n}Title$c_r': '$c_n$title_from_parse$c_r'." 2
                log_out "Parsing Serial ID from map using 'Title': '$title_from_parse'." 2

                if [[ $is_last_title -eq 0 ]] ; then
                    matches=$(grep -s ",$title_from_parse," "$file_map" | wc -l)
                else
                    matches=$(grep -s ",$title_from_parse\$" "$file_map" | wc -l)
                fi

                if [[ $matches == "0" ]] ; then
                    if [[ $is_last_title -eq 0 ]] ; then
                        matches=$(grep -s ",\"$title_from_parse\"," "$file_map" | wc -l)
                    else
                        matches=$(grep -s ",\"$title_from_parse\"\$" "$file_map" | wc -l)
                    fi

                    if [[ $matches == "1" ]] ; then
                        let match_is_quoted=1
                    fi
                fi

                if [[ $matches != "1" ]] ; then
                    echo_error "Too many or too few matches for '$c_n$directory_name$c_e', using Title '$c_n$title_from_parse$c_e'." 4
                    echo_out2
                    log_error "Too many or too few matches for '$directory_name', using Title '$title_from_parse'." 4

                    failure=1
                    let i++
                    continue
                fi

                if [[ $match_is_quoted -eq 0 ]] ; then
                    if [[ $is_last_title -eq 0 ]] ; then
                        serial_id_from_parse=$(grep -s ",$title_from_parse," "$file_map" | sed -e 's|,.*$||')
                    else
                        serial_id_from_parse=$(grep -s ",$title_from_parse\$" "$file_map" | sed -e 's|,.*$||')
                    fi
                else
                    if [[ $is_last_title -eq 0 ]] ; then
                        serial_id_from_parse=$(grep -s ",\"$title_from_parse\"," "$file_map" | sed -e 's|,.*$||')
                    else
                        serial_id_from_parse=$(grep -s ",\"$title_from_parse\"\$" "$file_map" | sed -e 's|,.*$||')
                    fi
                fi

                if [[ $serial_id_from_parse == "" ]] ; then
                    echo_error "Failed to load Serial ID for '$c_n$directory_name$c_e', using Title '$c_n$title_from_parse$c_e'." 4
                    echo_out2
                    log_error "Failed to load Serial ID for '$directory_name', using Title '$title_from_parse'." 4

                    failure=1
                    let i++
                    continue
                fi
            fi

            if [[ $serial_id_from_parse != "" ]] ; then
                echo_out_e "Validating Serial ID '$c_n$serial_id$c_r' against mapping file Serial ID: '$c_n$serial_id_from_parse$c_r'." 2
                log_out "Validating Serial ID '$serial_id' against mapping file Serial ID: '$serial_id_from_parse'." 2

                if [[ $serial_id == $serial_id_from_parse ]] ; then
                    echo_out_e "Serial ID '$c_n$serial_id$c_r' is valid." 4
                    log_out "Serial ID '$serial_id' is valid." 4
                else
                    echo_error "Failed to match Serial ID: directory Serial ID = '$c_n$serial_id$c_e', mapping file Serial ID = '$c_n$serial_id_from_parse$c_e'." 4
                    echo_out2
                    log_error "Failed to match Serial ID: directory Serial ID = '$serial_id', mapping file Serial ID = '$serial_id_from_parse'." 4

                    failure=1
                    let i++
                    continue
                fi
            fi
        else
            echo_out_e "Serial ID '$c_n$serial_id$c_r' is assumed to be valid." 2
            log_out "Serial ID '$serial_id' is assumed to be valid." 2
        fi

        if [[ $process_action == "rename" ]] ; then
            echo_out_e "Renaming directory from '$c_n$directory_name$c_r' to (Serial ID): '$c_n$serial_id$c_r'." 2
            log_out "Renaming directory from '$directory_name' to (Serial ID): '$serial_id'." 2

            new_name=$serial_id
            if [[ -d $new_name ]] ; then
                new_name=${serial_id}.duplicate-$RANDOM
                echo_warn "Duplicate Serial ID detected for '$c_n$directory_name$c_w', renaming to '$c_n$new_name$c_w'." 2
                log_out "Duplicate Serial ID detected for '$directory_name', renaming to '$new_name'." 2
            fi

            if [[ $new_name == "" ]] ; then
                echo_error "Cannot Rename: '$c_n$directory_name$c_e', No valid Serial ID found." 2
                echo_out2
                log_error "Cannot Rename: '$directory_name', No valid Serial ID found." 2

                failure=1
                let i++
                continue
            fi

            mv "$directory" "$parent_directory$new_name"
            if [[ $? -ne 0 ]] ; then
                echo_error "Failed to Rename: '$c_n$directory$c_e' to '$c_n$parent_directory$new_name$c_e'." 2
                echo_out2
                log_error "Failed to Rename: '$directory' to '$parent_directory$new_name'." 2

                failure=1
                let i++
                continue
            fi
        fi

        let i++
    done

    return $failure
}

parse_doi_or_title() {
    if [[ $parse_doi -eq 0 && $parse_title -eq 0 ]] ; then
        return 0
    fi

    local -i parse_failed=1

    doi_from_parse=
    title_from_parse=

    if [[ $parse_doi -eq 1 ]] ; then
        doi_from_parse=$(grep -so '<dcvalue element="relation" qualifier="uri" language="en">.*</dcvalue>' $directory/dublin_core.xml | sed -e 's|<dcvalue element="relation" qualifier="uri" language="en">||' -e 's|</dcvalue>||')

        if [[ $? -eq 0 ]] ; then
            if [[ $doi_from_parse != "" ]] ; then
                let parse_failed=0
            fi
        else
            doi_from_parse=
            let parse_failed=1
        fi
    fi

    if [[ $parse_title -eq 1 && ($parse_failed -eq 1 || $parse_doi -eq 0) ]] ; then
        title_from_parse=$(grep -so '<dcvalue element="title" language="en">.*</dcvalue>' $directory/dublin_core.xml | sed -e 's|<dcvalue element="title" language="en">||' -e 's|</dcvalue>||')

        if [[ $? -eq 0 ]] ; then
            if [[ $title_from_parse != "" ]] ; then
                let parse_failed=0
            fi
        else
            title_from_parse=
            let parse_failed=1
        fi
    fi

    if [[ $parse_failed -eq 1 ]] ; then
        if [[ $parse_doi -eq 1 ]] ; then
            if [[ $parse_title -eq 1 ]] ; then
                echo_out2
                echo_error "Unable to find doi or title." 2
                echo_out2
                log_error "Unable to find doi or title." 2
            else
                echo_out2
                echo_error "Unable to find doi." 2
                echo_out2
                log_error "Unable to find doi." 2
            fi
        elif [[ $parse_title -eq 1 ]] ; then
            echo_out2
            echo_error "Unable to find title." 2
            echo_out2
            log_error "Unable to find title." 2
        fi
    fi

    return $parse_failed
}

log_error() {
    local message=$1
    local depth=$2

    log_pad $depth
    echo "Error: $message" >> $log_file
}

log_warn() {
    local message=$1
    local depth=$2

    log_pad $depth
    echo "Warning: $message" >> $log_file
}

log_out() {
    local message=$1
    local depth=$2

    log_pad $depth
    echo "$message" >> $log_file
}

log_pad() {
    local -i depth=$1

    if [[ $depth -gt 0 ]] ; then
        printf "%${depth}s" " " >> $log_file
    fi
}

log_pad() {
    local -i depth=$1

    if [[ $depth -gt 0 ]] ; then
        printf "%${depth}s" " " >> $log_file
    fi
}

echo_out() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 0 ]] ; then
        echo_pad $depth
        echo "$message"
    fi
}

echo_out2() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 0 || $output_mode -eq 2 ]] ; then
        echo_pad $depth
        echo "$message"
    fi
}

echo_out3() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 2 || $output_mode -eq 3 ]] ; then
        echo_pad $depth
        echo "$message"
    fi
}

echo_out_e() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 0 ]] ; then
        echo_pad $depth
        echo -e "$message"
    fi
}

echo_out_e2() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 0 || $output_mode -eq 2 ]] ; then
        echo_pad $depth
        echo -e "$message"
    fi
}

echo_progress() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 2 || $output_mode -eq 3 ]] ; then
        if [[ $progress_printed -eq 0 ]] ; then
            let progress_printed=1
        else
            echo_clear
            echo -ne "\r$c_r"
        fi

        echo_pad $depth
        echo_count "$message"
        echo -ne "$message"
    fi
}

echo_error() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 0 || $output_mode -eq 2 ]] ; then
        # remove progress line so that the current warning or error can replace it.
        if [[ $progress_printed -eq 1 && $output_mode -eq 2 ]] ; then
            echo_progress
        fi

        echo_pad $depth
        echo -e "${c_e}ERROR: $message$c_r"

        if [[ $progress_printed -eq 1 && $output_mode -eq 2 ]] ; then
            let progress_printed=0
        fi
    fi
}

echo_warn() {
    local message=$1
    local depth=$2

    if [[ $output_mode -eq 0 || $output_mode -eq 2 ]] ; then
        # remove progress line so that the current warning or error can replace it.
        if [[ $progress_printed -eq 1 && $output_mode -eq 2 ]] ; then
            echo_progress
        fi

        echo_pad $depth
        echo -e "${c_w}WARNING: $message$c_r"

        if [[ $progress_printed -eq 1 && $output_mode -eq 2 ]] ; then
            let progress_printed=0
        fi
    fi
}

echo_pad() {
    local -i depth=$1

    if [[ $depth -gt 0 ]] ; then
        printf "%${depth}s" " "
    fi
}

echo_count() {
    local c_r=""
    local c_t=""
    local c_e=""
    local c_w=""
    local c_h=""
    local c_n=""
    local c_i=""
    local message="$1"

    let echo_buffer_count=${#message}
}

echo_clear() {
    if [[ $echo_buffer_count -gt 0 && $progress_printed -eq 1 ]] ; then
        echo -ne "\r"
        printf "%${echo_buffer_count}s" " "
    fi

    let echo_buffer_count=0
}

print_help() {
    local default_column_names=

    let i=0
    while [[ $i -lt ${#columns[@]} ]] ; do
        default_column_names="${default_column_names},${columns[$i]}"
        let i++
    done

    default_column_names=$(echo "$default_column_names" | sed -e 's|^,||')

    echo_out
    echo_out_e "${c_t}DSpace SAF Rename Directory$c_r"
    echo_out
    echo_out_e "Given a ${c_n}source directory${c_r}, this renames all top-level sub-directories to the names specified in a provided mapping file."
    echo_out
    echo_out_e "This expects the top-level sub-directories to be structured according to the SAFCreator format such that each directory represents a row number in a CSV spreadsheet starting at row 2."
    echo_out_e "With row 1 being the column headers for the spreadsheet."
    echo_out
    echo_out_e "The mapping file is expected to be of the following format:"
    echo_out_e "1) The mapping data must start at row 2, to map the current directory names to the row in this CSV spreadsheet."
    echo_out_e "2) The first column in the mapping file must represent a unique identifier."
    echo_out_e "3) The first column in the mapping file is required for every single row."
    echo_out_e "4) All subsequent columns are optional but if the column names '${c_n}DOI${c_r}' or '${c_n}Title${c_r}' are used, then additional validation is performed."
    echo_out_e "5) The default column names are: '${c_n}$default_column_names${c_r}'."
    echo_out
    echo_out_e "Each of the top-level sub-directories whose directory name matches a row number in the mapping file, must have a '${c_n}dublin_core.xml${c_r}' file."
    echo_out
    echo_out_e "The entire mapping file is not necessarily used, only top-level sub-directories are used for processing the mapping file."
    echo_out
    echo_out_e "${c_h}Usage:$c_r"
    echo_out_e "  $c_i$script_pathname$c_r ${c_n}[${c_r}options${c_n}]${c_r} ${c_n}<${c_r}source directory${c_n}>${c_r}"
    echo_out
    echo_out_e "${c_h}Options:$c_r"
    echo_out_e " -${c_i}c${c_r}, --${c_i}columns${c_r}   Specify custom columns as defined in the mapping file, comma separated."
    echo_out_e " -${c_i}h${c_r}, --${c_i}help${c_r}      Print this help screen."
    echo_out_e "     --${c_i}legacy${c_r}    Enable compatibility mode with legacy software versions, such as Bash 3.x."
    echo_out_e " -${c_i}l${c_r}, --${c_i}log_file${c_r}  Specify a custom log file name (currently: '$c_n$log_file$c_r')."
    echo_out_e " -${c_i}m${c_r}, --${c_i}map${c_r}       Specify the mapping CSV file."
    echo_out_e " -${c_i}n${c_r}, --${c_i}no_color${c_r}  Do not apply color changes when printing output to screen."
    echo_out_e " -${c_i}P${c_r}, --${c_i}progress${c_r}  Display progress instead of normal output."
    echo_out_e " -${c_i}s${c_r}, --${c_i}silent${c_r}    Do not print to the screen."
    echo_out_e " -${c_i}V${c_r}, --${c_i}validate${c_r}  Do not perform renaming, only validate mapping file."
    echo_out
    echo_out_e "Warning: ${c_i}legacy${c_r} mode is not guaranteed to work as it only has workarounds for known issues."
    echo_out
}

main "$@"

unset main
unset parse_doi_or_title
unset process_content
unset log_error
unset log_warn
unset log_out
unset log_pad
unset echo_out
unset echo_out_e
unset echo_out2
unset echo_out3
unset echo_out_e2
unset echo_progress
unset echo_error
unset echo_warn
unset echo_pad
unset echo_count
unset echo_clear
unset print_help
