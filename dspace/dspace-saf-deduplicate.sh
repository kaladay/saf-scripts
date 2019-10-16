#!/bin/bash
#
# Find and remove duplicate documents specified in an SAF Batch import directory.
#
# This works by searching for the files called 'contents', which specify all documents provided in the SAF.
# This will be used as a list of files to process.
# The processed files will be checksumed and renamed after duplicates are removed.
#
# When "--preserve" is not used, all files will be renamed to something like 'document-1.pdf' (original extension will be preserved).
#
# Some systems still use very old versions of the software (such as bash 3
#
# This expects a bash of at least version 4, but provides some limited work-arounds for known problems with bash version 3.
#
# This provides custom support for the "md5" program as opposed to "md5sum" that is typically found on OS-X systems.
# The "md5" program has a different output structure and must be parsed differently.
#
# Set "sort_command" to an empty string to disable sorting.
# Sorting, via the sort command, is used to ensure consistent processing order so that the logs of multiple different executions can be compared.
# Sorting is set to "numeric" (sorts numeric is not a "numeric order" but a "numeric string order" such that '15' would come before '275', but '275' would come before '58'.
#
# Example Usage:
#   ```
#   dspace-saf-deduplicate.sh -m mapping.csv source_directory
#   ```
#
# depends on the following userspace commands:
#   awk (or grep), dirname, basename, date (optional), find, sed, md5sum (or compatible, like shasum) (special support for 'md5' also exists), touch (optional), and sort (optional).

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

    # additional parameters
    local start_stamp=
    local -i preserve=0
    local -i progress_printed=0
    local -i echo_buffer_count=0
    local -i alternative_checksum=0
    local source_directory=
    local document_name_prefix="document-"
    local contents_file="contents"
    local bundle_name="$(echo -e "\tbundle:ORIGINAL")"

    # logging
    local log_file="changes.log"

    # commands
    local checksum_command=""
    local find_command="find"
    local grep_command=""
    local sort_command="sort"

    if [[ $(type -p date) ]] ; then
        log_file="changes-$(date +'%Y_%m_%d').log"

        start_stamp=$(date +'%Y/%m/%d %_I:%M:%S %P %z')
    fi

    if [[ $(type -p awk) ]] ; then
        grep_command="awk"
    elif [[ $(type -p grep) ]] ; then
        grep_command="grep"
    fi

    if [[ $(type -p md5sum) ]] ; then
        checksum_command="md5sum"
    elif [[ $(type -p shasum) ]] ; then
        checksum_command="shasum"
    elif [[ $(type -p md5) ]] ; then
        checksum_command="md5"
        let alternative_checksum=1
    fi

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
                if [[ $parameter == "-c" || $parameter == "--checksum" ]] ; then
                    grab_next="$parameter"
                elif [[ $parameter == "-h" || $parameter == "--help" ]] ; then
                    let get_help=1
                elif [[ $parameter == "-f" || $parameter == "--file" ]] ; then
                    grab_next="$parameter"
                elif [[ $parameter == "--legacy" ]] ; then
                    let legacy=1
                elif [[ $parameter == "-l" || $parameter == "--log_file" ]] ; then
                    grab_next="$parameter"
                elif [[ $parameter == "-n" || $parameter == "--no_color" ]] ; then
                    c_r=""
                    c_t=""
                    c_e=""
                    c_w=""
                    c_h=""
                    c_n=""
                    c_i=""
                elif [[ $parameter == "-p" || $parameter == "--preserve" ]] ; then
                    let preserve=1
                elif [[ $parameter == "-r" || $parameter == "--rename_to" ]] ; then
                    grab_next="$parameter"
                elif [[ $parameter == "-s" || $parameter == "--silent" ]] ; then
                    if [[ $output_mode -eq 0 ]] ; then
                        let output_mode=1
                    elif [[ $output_mode -eq 2 ]] ; then
                        let output_mode=3
                    fi
                elif [[ $parameter == "-P" || $parameter == "--progress" ]] ; then
                    if [[ $output_mode -eq 0 ]] ; then
                        let output_mode=2
                    elif [[ $output_mode -eq 1 ]] ; then
                        let output_mode=3
                    fi
                elif [[ $source_directory == "" ]] ; then
                    source_directory=$(echo "$parameter" | sed -e 's|//*|/|g' -e 's|/*$|/|')
                else
                    extra_parameters[${extra_parameters_total}]=$parameter
                    let extra_parameters_total++
                fi
            else
                if [[ $grab_next == "-c" || $grab_next == "--checksum" ]] ; then
                    checksum_command=$(echo "$parameter" | sed -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||')
                    grab_next=
                elif [[ $grab_next == "-f" || $grab_next == "--file" ]] ; then
                    contents_file=$(echo "$parameter" | sed -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||')
                    grab_next=
                elif [[ $grab_next == "-l" || $grab_next == "--log_file" ]] ; then
                    log_file=$(echo "$parameter" | sed -e 's|//*|/|g')
                    grab_next=
                elif [[ $grab_next == "-r" || $grab_next == "--rename_to" ]] ; then
                    document_name_prefix="$parameter"
                    grab_next=
                else
                    break
                fi
            fi
        done
    fi

    # if using alternative "md5" program, change the checksum processing method because 'md5' has a different output structure than say 'md5sum'.
    if [[ $checksum_command == "md5" ]] ; then
        let alternative_checksum=1
    fi

    if [[ $(type -p basename) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (basename) command '${c_n}basename$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p $checksum_command) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (checksum) command '$c_n$checksum_command$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p dirname) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (dirname) command '${c_n}dirname$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p $find_command) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (find) command '$c_n$find_command$c_r'"
        echo_out2
        return 1
    fi

    if [[ $grep_command == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (grep) command '$c_n$grep_command$c_r'"
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
        echo_error "Missing parameter for '$c_n$grab_next$c_e'"
        echo_out2
        return 1
    elif [[ "$checksum_command" == "" || $(type -p "$checksum_command") == "" ]] ; then
        echo_out2
        echo_error "Invalid checksum program '$c_n$checksum_command$c_e'"
        echo_out2
        return 1
    elif [[ "$contents_file" == "" || $(basename $contents_file) != "$contents_file" ]] ; then
        echo_out2
        echo_error "Invalid contents_file specified '$c_n$contents_file$c_e'"
        echo_out2
        return 1
    elif [[ $extra_parameters_total -gt 0 ]] ; then
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

    if [[ ! -r $source_directory ]] ; then
        echo_out2
        echo_error "The source directory '$c_n$source_directory$c_e' is not found or is not readable."
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
    local set=
    local sets=
    local file_path=
    local -i document_current=1
    local -i document_total=0

    echo_out2
    echo_out_e2 "${c_t}Analyzing Source Directory:$c_r $c_n$source_directory$c_r"

    log_out
    if [[ $start_stamp == "" ]] ; then
        log_out "====== Analyzing Source Directory: '$source_directory' ======"
    else
        echo_out "Started On: $start_stamp" 2
        log_out "====== Analyzing Source Directory: '$source_directory' ($start_stamp) ======"
    fi

    if [[ $sort_command != "" ]] ; then
        sets=$($find_command $source_directory -nowarn -type f -name $contents_file | $sort_command -V)
    else
        sets=$($find_command $source_directory -nowarn -type f -name $contents_file)
    fi

    if [[ $sets == "" ]] ; then
        echo_out2
        echo_error "Did not find any files named '$c_n$contents_file$c_e' inside of the directory '$c_n$source_directory$c_e'."
        echo_out2
        log_error "Did not find any files named '$c_n$contents_file$c_e' inside of the directory '$c_n$source_directory$c_e'."
        return 1
    fi

    if [[ $output_mode -eq 2 || $output_mode -eq 3 ]] ; then
        count_documents
    fi

    for set in $sets ; do
        echo_out
        echo_out_e "${c_t}Now Processing Set:$c_r $c_n$set$c_r"

        log_out
        log_out "===== Begin Set: '$set' ====="

        file_path=$(dirname $set)

        if [[ $file_path == "" ]] ; then
            echo_out2
            echo_warn "Failed to process directory path for '$c_n$set$c_w', skipping set." 2
            log_warn "Failed to process directory path for '$set', skipping set."
            continue
        fi

        if [[ ! -w $file_path ]] ; then
            echo_out2
            echo_warn "The directory path '$c_n$file_path$c_w' is not writable, skipping set." 2
            log_warn "The directory path '$file_path' is not writable, skipping set."
            continue
        fi

        file_path=${file_path}/

        process_documents

        echo_out_e "    ${c_n}Done$c_r"
    done

    if [[ $output_mode -eq 2 || $output_mode -eq 3 ]] ; then
        let document_current--
        echo_progress "${c_t}Finished Processing:$c_r $c_i$document_current$c_r of $c_i$document_total$c_r documents."
        echo_out3
    fi
}

process_documents() {
    local document=
    local documents=$(sed -e 's|bundle:ORIGINAL| |g' $set)
    local checksum=
    local index=

    if [[ $legacy -eq 1 ]] ; then
        local -a checksums=()
        local -a checksums_order=()
        local -a checksums_all=()

        # for compatibility with systems whose bash does no support associative arrays (-A).
        # "checksums_index" is used to store the checksum for "checksums".
        # "documents_all" is used to fetch the index for document names for "checksums_all" index array.
        local -a checksums_index=()
        local -a documents_all=()
    else
        local -A checksums=()
        local -A checksums_order=()
        local -A checksums_all=()
    fi

    if [[ $documents == "" ]] ; then
        echo_out2
        echo_warn "No documents described in '$c_n$set$c_w', skipping set." 2
        echo_out2
        log_warn "No documents found in '$set', skipping set."
        return
    fi

    for document in $documents ; do
        echo_progress "${c_t}Processing:$c_r $document_current of $document_total, set: '$c_i$set$c_r', document name: '$c_i$document$c_r'."

        if [[ ! -r $file_path$document ]] ; then
            echo_out2
            echo_error "Document '$c_n$file_path$document$c_e' not found or not readable, skipping set." 2
            echo_out2
            log_error "Not found or readable document '$file_path$document', skipping set."
            let document_current++
            continue
        fi

        if [[ ! -w $file_path$document ]] ; then
            echo_out2
            echo_error "Document '$c_n$file_path$document$c_e' not writable, skipping set." 2
            echo_out2
            log_error "Not writable document '$file_path$document', skipping set."
            let document_current++
            continue
        fi

        echo_out_e "    Generating checksum for '$c_h$file_path$document$c_r'."

        # parse the checksum command in such a way that special-case checksum output formats can be handled, namely 'md5'.
        parse_checksum $file_path$document
        if [[ $? -ne 0 ]] ; then
            echo_out2
            echo_error "Checksum generation for '$c_n$file_path$document$c_e' failed, skipping set." 2
            echo_out2
            log_error "Checksums generation failed for document '$file_path$document', skipping set."
            let document_current++
            continue
        fi

        if [[ $checksum == "" ]] ; then
            echo_out2
            echo_error "Failed to process checksum results for '$c_n$file_path$document$c_e', skipping set." 2
            echo_out2
            log_error "Process checksum failed for document '$file_path$document', skipping set."
            let document_current++
            continue
        fi

        # populate $index variable from $checksum variable in such a way that legacy bash versions, namely bash 3, can work.
        find_checksum_index

        if [[ $index == "" ]] ; then
            create_checksum_index_if_new

            echo_out_e "        Checksum: (new)             '$c_i$checksum$c_r'."
            log_out "New checksum found '$checksum', document '$file_path$document'."
            checksums["$index"]="$document";

            # array order is not guaranteed.
            # to attempt to preserve document order, store the index id based on the total checksums in the set.
            checksums_order["$index"]=${#checksums[*]};
            if [[ $legacy -eq 1 ]] ; then
                checksums_index["$index"]="$checksum"
            fi
        else
            echo_out_e "        Checksum: (duplicate) '$c_i$checksum$c_r'."
            log_out "Duplicate checksum found '$checksum', document '$file_path$document'."
        fi

        # populate $index variable from $document variable in such a way that legacy bash versions, namely bash 3, can work.
        find_document_index
        create_document_index_if_new

        checksums_all["$index"]="$checksum"

        if [[ $legacy -eq 1 ]] ; then
            documents_all["$index"]="$document"
        fi

        echo_out
        let document_current++
    done

    rename_documents_to_checksum

    if [[ $? -eq 0 ]] ; then
        rename_checksums_to_document
    fi

    if [[ $? -eq 0 ]] ; then
        rebuild_contents_file
    fi
}

count_documents() {
    local document=
    local documents=

    for set in $sets ; do
        documents=$(grep -o '^document-[[:digit:]]*\.pdf\>' $set)
        for document in $documents ; do
            let document_total++
        done
    done
}

rename_documents_to_checksum() {
    local -i i=0
    local -i total=${#checksums_all[*]}
    local file_name_old=
    local file_name_new=
    local extension=
    local checksum=
    local -i failure=0
    local index=

    if [[ $total -eq 0 ]] ; then
        return 0
    fi

    # renaming files to their checksum name will effectively result in duplicate files being removed.
    for index in ${!checksums_all[@]} ; do
        if [[ $legacy -eq 1 ]] ; then
            file_name_old=${documents_all[$index]}
            checksum=${checksums_all[$index]}
        else
            file_name_old="$index"
            checksum=${checksums_all[$file_name_old]}
        fi

        parse_file_extension "$file_name_old"
        file_name_new=$checksum$extension

        mv $file_path$file_name_old $file_path$file_name_new
        if [[ $? -ne 0 ]] ; then
            echo_out2
            echo_error "Something went wrong while moving '$c_n$file_path$file_name_old$c_e' to '$c_n$file_path$file_name_new$c_e'." 6
            echo_out2
            log_error "Failed to move '$file_path$file_name_old' to '$file_path$file_name_new'."
            break
        else
            echo_out_e "Renamed '$c_n$file_path$file_name_old$c_r' to '$c_n$file_path$file_name_new$c_r'." 2
            log_out "Renamed '$file_path$file_name_old' to '$file_path$file_name_new'."
        fi
    done

    for index in ${!checksums_all[*]} ; do
        if [[ $legacy -eq 1 ]] ; then
            file_name_old=${documents_all[$index]}
        else
            file_name_old="$index"
        fi

        if [[ -e $file_path$file_name_old ]] ; then
            echo_out2
            echo_error "File '$c_n$file_path$file_name_old$c_e' not renamed, resetting changes to entire set." 4
            echo_out2
            log_error "File not renamed '$file_path$file_name_old', resetting changes to entire set."
            let failure=1
            break
        fi
    done

    if [[ $failure -eq 1 ]] ; then
        local file_to_delete=
        local files_to_delete=
        local -i revert_failure=0

        for index in ${!checksums_all[*]} ; do
            if [[ $legacy -eq 1 ]] ; then
                file_name_old=${documents_all[$index]}
                checksum=${checksums_all[$index]}
            else
                file_name_old="$index"
                checksum=${checksums_all[$file_name_old]}
            fi

            parse_file_extension "$file_name_old"
            file_name_new=$checksum$extension

            if [[ -f $file_path$file_name_new && ! -f $file_path$file_name_old ]] ; then
                cp $file_path$file_name_new $file_path$file_name_old

                if [[ $? -eq 0 ]] ; then
                    files_to_delete="$files_to_delete$file_name_new "
                    log_out "Restored '$file_path$file_name_old' from '$file_path$file_name_new'."
                else
                    log_warn "Failed to restore '$file_path$file_name_old' from '$file_path$file_name_new'."
                    let revert_failure=1
                fi
            fi
        done

        if [[ $revert_failure -eq 0 ]] ; then
            for file_to_delete in files_to_delete ; do
                if [[ -f $file_path$file_to_delete ]] ; then
                    rm $file_path$file_to_delete

                    if [[ $? -ne 0 ]] ; then
                        echo_out
                        echo_warn "Something went wrong while deleting '$c_n$file_path$file_to_delete$c_w'." 6
                        echo_out
                        log_warn "Attempted but failed to delete '$file_path$file_to_delete'."
                    else
                        log_out "Deleted '$file_path$file_to_delete'."
                    fi
                fi
            done
        fi

        return 1
    fi

    return 0
}

rename_checksums_to_document() {
    local -i total=${#checksums[*]}
    local checksum=
    local extension=
    local order=
    local file_name_old=
    local file_name_checksum=
    local file_name_desired=

    if [[ $total -eq 0 ]] ; then
        return 0
    fi

    for index in ${!checksums[*]} ; do
        if [[ $legacy -eq 1 ]] ; then
            checksum=${checksums_index[$index]}
            file_name_old=${checksums[$index]}
            order=${checksums_order[$index]}
        else
            checksum="$index"
            file_name_old=${checksums[$checksum]}
            order=${checksums_order[$checksum]}
        fi

        parse_file_extension "$file_name_old"
        file_name_checksum=$checksum$extension

        if [[ $preserve -eq 0 ]] ; then
            file_name_desired=$document_name_prefix$order$extension
        else
            file_name_desired=$file_name_old
        fi

        mv $file_path$file_name_checksum $file_path$file_name_desired
        if [[ $? -ne 0 ]] ; then
            echo_out2
            echo_error "Something went wrong while moving '$c_n$file_path$file_name_checksum$c_e' to '$c_n$file_path$file_name_desired$c_e'." 6
            echo_out2
            log_error "Attempted but failed to move '$file_path$file_name_checksum' to '$file_path$file_name_desired'."
            return 1
        else
            echo_out_e "Renamed '$c_n$file_path$file_name_checksum$c_r' to '$c_n$file_path$file_name_desired$c_r'." 2
            log_out "Renamed '$file_path$file_name_checksum' to '$file_path$file_name_desired'."
        fi
    done

    return 0
}

rebuild_contents_file() {
    local -i i=1
    local -i total=${#checksums[*]}
    local extension=
    local file_name=
    local document_line=
    local -i failure=0

    if [[ $total -eq 0 ]] ; then
        rm $file_path$contents_file

        if [[ $? -ne 0 ]] ; then
            echo_out
            echo_warn "Something went wrong while deleting '$c_n$file_path$contents_file$c_w'." 6
            echo_out
            log_warn "Failed to delete unnecessary '$file_path$contents_file'."
            let failure=1
        else
            log_out "Deleted unnecessary '$file_path$contents_file' (no files to upload)."
        fi

        return $failure
    fi

    echo -n > $file_path$contents_file

    if [[ $? -ne 0 ]] ; then
        echo_out2
        echo_error "Something went wrong while clearing '$c_n$file_path$contents_file$c_e'." 6
        echo_out2
        log_error "Failed to clear '$file_path$contents_file'."
        return 1
    else
        log_out "Cleared '$file_path$contents_file'."
    fi

    let i=0
    for checksum in ${!checksums[*]} ; do
        file_name=${checksums[$checksum]}

        if [[ $preserve -eq 0 ]] ; then
            let i++
            parse_file_extension "$file_name"
            document_line="$document_name_prefix$i$extension$bundle_name"
        else
            document_line="$file_name$bundle_name"
        fi

        echo "$document_line" >> $file_path$contents_file &&
        echo >> $file_path$contents_file

        if [[ $? -ne 0 ]] ; then
            echo_out2
            echo_error "Something went wrong while appending '$c_n$document_line$c_e' to '$c_n$file_path$contents_file$c_e'." 6
            echo_out2
            log_error "Failed to append '$document_line' to '$file_path$contents_file'."
            let failure=1
        else
            log_out "Appended '$document_line' to '$file_path$contents_file'."
        fi
    done

    # remove last line from contents file (which is an extra empty line).
    sed -i -e '$d' $file_path$contents_file

    if [[ $? -ne 0 ]] ; then
        echo_out2
        echo_warn "Something went wrong while remove last line from '$c_n$file_path$contents_file$c_w'." 6
        echo_out2
        log_warn "Failed to remove last line from '$file_path$contents_file'."
        let failure=1
    fi

    return $failure
}

parse_checksum() {
    local file="$1"
    local unparsed=

    unparsed=$($checksum_command $file)
    if [[ $? -ne 0 ]] ; then
        return 1
    fi

    if [[ alternative_checksum -eq 1 ]] ; then
        checksum=$(echo $unparsed | sed -e 's|^.* = ||')
    else
        checksum=$(echo $unparsed | sed -e 's|[[:space:]][[:space:]]*[^[:space:]].*$||')
    fi

    return 0
}

find_checksum_index() {
    index=
    if [[ $legacy -eq 1 ]] ; then
        local -i total=${#checksums_index[*]}
        local -i current=0

        if [[ $total == "" || $total -eq 0 ]] ; then
            return
        fi

        while [[ $current -lt $total ]] ; do
            if [[ ${checksums_index[$current]} == "$checksum" ]] ; then
                let index=$current
                break
            fi

            let current++
        done
    else
        if [[ ${checksums[$checksum]} != "" ]] ; then
            index="$checksum"
        fi
    fi
}

find_document_index() {
    index=
    if [[ $legacy -eq 1 ]] ; then
        local -i total=${#documents_index[*]}
        local -i current=0

        if [[ $total == "" || $total -eq 0 ]] ; then
            return
        fi

        while [[ $current -lt $total ]] ; do
            if [[ ${documents_index[$current]} == "$document" ]] ; then
                let index=$current
                break
            fi

            let current++
        done
    else
        if [[ ${checksums_all[$document]} != "" ]] ; then
            index="$document"
        fi
    fi
}

# meant to be called after find_checksum_index() in which if the $checksum was not found then a new index needs to be created.
create_checksum_index_if_new() {
    if [[ $index == "" ]] ; then
        # in legacy mode, append checksum if no index was found, then set the index.
        if [[ $legacy -eq 1 ]] ; then
            index=${#checksums_index[*]}

            # index arrays must have each key initialized via an array append before the key can be directly accessed to be modified.
            checksums_index+=("")
        else
            index="$checksum"
        fi
    fi
}

# meant to be called after find_document_index() in which if the $document was not found then a new index needs to be created.
create_document_index_if_new() {
    if [[ $index == "" ]] ; then
        # in legacy mode, append document if no index was found, then set the index.
        if [[ $legacy -eq 1 ]] ; then
            index=${#documents_index[*]}

            # index arrays must have each key initialized via an array append before the key can be directly accessed to be modified.
            documents_index+=("")
        else
            index="$document"
        fi
    fi
}

parse_file_extension() {
    local filename="$1"

    if [[ $grep_command == "awk" ]] ; then
        extension=$(echo $filename | awk "match(\$0, /\.[^.]*\$/) { print substr(\$0, RSTART, RLENGTH) }")
    else
        extension=$(echo $filename | grep -so '\.[^.]*$')
    fi
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
    echo_out
    echo_out_e "${c_t}DSpace SAF Import De-Duplicator$c_r"
    echo_out
    echo_out_e "Given a ${c_n}source directory${c_r}, this removes duplicates and renames all files specified by '$c_n$contents_file$c_r' files found within the source directory."
    echo_out
    echo_out_e "The specified source directories will be recursively search the given source directories, operating on any directories containg a 'contents' file."
    echo_out
    echo_out_e "${c_h}Usage:$c_r"
    echo_out_e "  $c_i$script_pathname$c_r ${c_n}[${c_r}options${c_n}]${c_r} ${c_n}<${c_r}source directory${c_n}>${c_r}"
    echo_out
    echo_out_e "${c_h}Options:$c_r"
    echo_out_e " -${c_i}c${c_r}, --${c_i}checksum${c_r}   Specify a custom checksum utility (currently: '$c_n$checksum_command$c_r')."
    echo_out_e " -${c_i}f${c_r}, --${c_i}file${c_r}       Specify a custom 'contents' file (currently: '$c_n$contents_file$c_r')."
    echo_out_e " -${c_i}h${c_r}, --${c_i}help${c_r}       Print this help screen."
    echo_out_e "     --${c_i}legacy${c_r}     Enable compatibility mode with legacy software versions, such as Bash 3.x."
    echo_out_e " -${c_i}l${c_r}, --${c_i}log_file${c_r}   Specify a custom log file name (currently: '$c_n$log_file$c_r')."
    echo_out_e " -${c_i}n${c_r}, --${c_i}no_color${c_r}   Do not apply color changes when printing output to screen."
    echo_out_e " -${c_i}p${c_r}, --${c_i}preserve${c_r}   Preserve the original file names instead of renaming."
    echo_out_e " -${c_i}P${c_r}, --${c_i}progress${c_r}   Display progress instead of normal output."
    echo_out_e " -${c_i}r${c_r}, --${c_i}rename_to${c_r}  Specify a custom rename to filename prefix (currently: '$c_n$document_name_prefix$c_r')."
    echo_out_e " -${c_i}s${c_r}, --${c_i}silent${c_r}     Do not print to the screen."
    echo_out
    echo_out_e "When --${c_i}preserve${c_r} is used, --${c_i}rename_to${c_r} is ignored."
    echo_out
    echo_out_e "Warning: ${c_i}legacy${c_r} mode is not guaranteed to work as it only has workarounds for known issues."
    echo_out_e "Warning: You may have to set both ${c_i}--legacy${c_r} and ${c_i}--checksum md5${c_r} if using you are using OS-X."
    echo_out
}

main "$@"

unset main
unset process_content
unset process_documents
unset count_documents
unset rename_documents_to_checksum
unset rename_checksums_to_document
unset rebuild_contents_file
unset parse_checksum
unset find_checksum_index
unset find_document_index
unset find_checksum_all_index
unset create_checksum_index_if_new
unset create_document_index_if_new
unset parse_file_extension
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
