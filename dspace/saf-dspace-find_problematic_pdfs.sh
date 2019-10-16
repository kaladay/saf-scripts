#!/bin/bash
#
# Find problems with downloaded PDFs.
#
# When PDFs are downloaded by SAFCreator, servers they are downloaded from do not always follow the HTTP standards or otherwise provide valid PDFs.
# For example, there are many servers that return 200 as well as set the mimetype to "application/pdf" and then they provide an HTML or plain text message saying "404 Not Found".
# Due to receiving a 200, SAFCreator does not know that the HTTP 200 is actually an HTTP 404 in disguise.
#
# This is search all top-level sub-directories, representing the downloaded SAF data, that are within a single source directory.
#
# A log file will be generated, containing the complete results of the process.
#
# A checksum directory will be created, which will contain files ending in the following extensions: ".duplicates", ".missing", and ".invalid".
# Each of these filenames (without the extension) represents the directory name that it is associated with.
# The ".duplicates" contains a list of all duplicate PDFs and their checksums for that directory.
# The ".missing" contains a list of all missing PDFs for that directory.
# The ".invalid" contains a list of all invalid PDFs and their checksums for that directory.
#
# As for the ".duplicates" files, only the duplicates are added such that if "document-1.pdf" and "document-2.pdf" are duplicates, only "document-2.pdf" will be present in that file.
#
# Example Usage:
#   ```
#   saf-dspace-find_problematic_pdfs.sh source_directory
#   ```
#
# depends on the following userspace commands:
#   awk (or grep), basename, bash, date (optional), find, sed, touch (optional), file, and md5sum (or compatible, like shasum) (special support for 'md5' also exists).

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
    local -i alternative_checksum=0
    local contents_file="contents"
    local bundle_name="bundle:ORIGINAL"
    local checksum_directory="checksums/"
    local source_directory=
    local write_directory=$(echo $PWD | sed -e 's|//*|/|g' -e 's|/*$|/|')

    # logging
    local log_file="analysis.log"

    # commands
    local checksum_command=""
    local find_command="find"
    local grep_command=""

    if [[ $(type -p date) ]] ; then
        log_file="analysis-$(date +'%Y_%m_%d').log"

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
                elif [[ $parameter == "--legacy" ]] ; then
                    let legacy=1
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
                elif [[ $parameter == "-w" || $parameter == "--write_directory" ]] ; then
                    grab_next="$parameter"
                elif [[ $source_directory == "" ]] ; then
                    source_directory=$(echo $parameter | sed -e 's|//*|/|g' -e 's|/*$|/|')
                else
                    extra_parameters[${extra_parameters_total}]="$parameter"
                    let extra_parameters_total++
                fi
            else
                if [[ $grab_next == "-c" || $grab_next == "--checksum" ]] ; then
                    checksum_command=$(echo "$parameter" | sed -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||')
                    grab_next=
                elif [[ $grab_next == "-w" || $grab_next == "--write_directory" ]] ; then
                    write_directory=$(echo "$parameter" | sed -e 's|//*|/|g' -e 's|/*$|/|')
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

    if [[ $(type -p $checksum_command) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (checksum) command '$c_n$checksum_command$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p file) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (file) command '${c_n}file$c_r'"
        echo_out2
        return 1
    fi

    if [[ $(type -p find) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (find) command '${c_n}find$c_r'"
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

    if [[ -d $write_directory$log_file ]] ; then
        echo_out2
        echo_error "The log file cannot be a directory '$c_n$write_directory$log_file$c_e'."
        echo_out2
        return 1
    fi

    if [[ $(type -p touch) != "" ]] ; then
        touch -f $write_directory$log_file
        if [[ $? -ne 0 ]] ; then
            echo_out2
            echo_error "Unable to write to log file '$c_n$write_directory$log_file$c_e'."
            echo_out2
            return 1
        fi
    fi

    process_directories
    return $?
}

process_directories() {
    local i=
    local -i failure=0
    local directories=
    local -i directories_total=0
    local directory=
    local directory_name=
    local pdfs=

    echo_out
    echo_out_e "${c_t}Analyzing Source Directory:$c_r $c_n$source_directory$c_r"

    log_out
    if [[ $start_stamp == "" ]] ; then
        log_out "====== Analyzing Source Directory: '$source_directory' ======"
    else
        echo_out "Started On: $start_stamp" 2
        log_out "====== Analyzing Source Directory: '$source_directory' ($start_stamp) ======"
    fi

    # build a list of directories within the specified source directory to process.
    for i in $($find_command $source_directory -nowarn -mindepth 1 -maxdepth 1 -type d ! -name '\.*') ; do
        directories["$directories_total"]=$(basename $i)
        let directories_total++
    done

    if [[ $directories_total -eq 0 ]] ; then
        echo_out2
        echo_warn "No Sub-Directories Found for Source Directory: '$c_n$source_directory$c_w'." 2
        echo_out2
        log_warn "No Sub-Directories Found for Source Directory: '$source_directory'." 2
        return 0
    fi

    for i in ${!directories[@]} ; do
        directory_name=${directories[$i]}
        directory="$directory_name/"
        echo_out
        echo_out_e "${c_t}Now Processing Directory:$c_r $c_n$directory_name$c_r"

        log_out
        log_out "===== Processing Directory: '$directory_name' ====="

        if [[ ! -d "$source_directory$directory" ]] ; then
            echo_error "Invalid Directory: '$c_n$directory_name$c_w'." 2
            echo_out2
            log_error "Invalid Directory: '$source_directory$directory'." 2
            continue
        fi

        if [[ ! -f "$source_directory$directory$contents_file" ]] ; then
            echo_warn "Missing Contents File: '$c_n$contents_file$c_w'." 2
            echo_out2
            log_warn "Missing Contents File: '$source_directory$directory$contents_file'." 2
            continue
        fi

        if [[ $grep_command == "awk" ]] ; then
            pdfs=$(awk "/$bundle_name\s*\$/" $source_directory$directory$contents_file | sed -e "s|[[:space:]]*$bundle_name[[:space:]]*\$||g")
        else
            pdfs=$(grep -s "\<$bundle_name\>[[:space:]]*\$" $source_directory$directory$contents_file | sed -e "s|[[:space:]]*$bundle_name[[:space:]]*\$||g")
        fi

        if [[ $pdfs == "" ]] ; then
            echo_warn "Empty Contents File: '$c_n$directory$contents_file$c_w'." 2
            echo_out2
            log_warn "Empty Contents File: '$source_directory$directory$contents_file'." 2
            continue
        fi

        validate_pdfs
        if [[ $? -ne 0 ]] ; then
            let failure=1
        fi
    done

    return $failure
}

validate_pdfs() {
    local -i failure=0
    local -i is_duplicate=0
    local pdf=
    local mime=
    local checksum=
    local -a checksums=()

    if [[ $legacy -eq 1 ]] ; then
        local -i i=0
        local -i checksums_length=0
    fi

    if [[ -f $write_directory$checksum_directory${directory_name}.duplicates ]] ; then
        rm -f $write_directory$checksum_directory${directory_name}.duplicates
        log_out "Removing existing duplicates file: '$write_directory$checksum_directory${directory_name}.duplicates'"
    fi

    for pdf in $pdfs ; do
        echo_out_e "  - PDF '$c_n$pdf$c_r'"
        log_out "  - PDF '$pdf'"

        if [[ ! -f $source_directory$directory$pdf ]] ; then
            echo_error "Missing PDF." 4
            log_error "Missing PDF for '$source_directory$directory$pdf'." 4

            if [[ ! -d $write_directory$checksum_directory ]] ; then
                mkdir -p $write_directory$checksum_directory
                if [[ $? -ne 0 ]] ; then
                    echo_error "Failed to create checksum directory: '$c_n$write_directory$checksum_directory$c_e'." 4
                    log_error "Failed to create checksum directory: '$write_directory$checksum_directory'."
                fi
            fi

            echo "$pdf" >> $write_directory$checksum_directory${directory_name}.missing
            log_out "Writing '$pdf' to '$write_directory$checksum_directory${directory_name}.missing'" 6

            let failure=1
            continue
        fi

        if [[ $legacy -eq 1 ]] ; then
            mime=$(file -b -I "$source_directory$directory$pdf" | sed -e 's|;.*$||')
        else
            mime=$(file -b -i "$source_directory$directory$pdf" | sed -e 's|;.*$||')
        fi

        if [[ $mime != "application/pdf" ]] ; then
            echo_error "Invalid PDF." 4
            log_error "Invalid PDF for '$source_directory$directory$pdf'." 4

            if [[ ! -d $write_directory$checksum_directory ]] ; then
                mkdir -p $write_directory$checksum_directory
                if [[ $? -ne 0 ]] ; then
                    echo_error "Failed to create checksum directory: '$c_n$write_directory$checksum_directory$c_e'." 4
                    log_error "Failed to create checksum directory: '$write_directory$checksum_directory'."
                fi
            fi

            echo "$pdf    $checksum" >> $write_directory$checksum_directory${directory_name}.invalid
            log_out "Writing '$pdf    $checksum' to '$write_directory$checksum_directory${directory_name}.invalid'" 6

            let failure=1
            continue
        fi

        parse_checksum "$source_directory$directory$pdf"
        if [[ $? -ne 0 ]] ; then
            echo_error "PDF Checksum generation failed." 4
            log_error "PDF Checksum generation failed for '$source_directory$directory$pdf'." 4
            let failure=1
            continue
        fi

        if [[ $checksum == "" ]] ; then
            echo_error "No PDF checksum generated." 4
            log_error "No PDF checksum generated for '$source_directory$directory$pdf'." 4
            let failure=1
            continue
        fi

        let is_duplicate=0
        if [[ $legacy -eq 0 ]] ; then
            # note: xx is prepended to checksum to prevent bash from interpreting the checksum as an integer.
            if [[ ${checksums["xx$checksum"]} == "$checksum" ]] ; then
                let is_duplicate=1
            fi
        else
            for i in ${!checksums[@]} ; do
                if [[ ${checksums[$i]} == "$checksum" ]] ; then
                    let is_duplicate=1
                    break
                fi
            done
        fi

        if [[ $is_duplicate -eq 1 ]] ; then
            echo_out "Is duplicate PDF." 4
            log_out "Is duplicate PDF." 4

            if [[ ! -d $write_directory$checksum_directory ]] ; then
                mkdir -p $write_directory$checksum_directory
                if [[ $? -ne 0 ]] ; then
                    echo_error "Failed to create checksum directory: '$c_n$write_directory$checksum_directory$c_e'." 4
                    log_error "Failed to create checksum directory: '$write_directory$checksum_directory'."
                    let failure=1
                fi
            fi

            echo "$pdf    $checksum" >> $write_directory$checksum_directory${directory_name}.duplicates
            log_out "Writing '$pdf    $checksum' to '$write_directory$checksum_directory${directory_name}.duplicates'" 6
        else
            echo_out "Is Unique PDF." 4
            log_out "Is Unique PDF." 4

            if [[ $legacy -eq 0 ]] ; then
                checksums["xx$checksum"]="$checksum"
            else
                checksums["$checksums_length"]="$checksum"
                let checksums_length++
            fi
        fi
    done

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

log_error() {
    local message=$1
    local depth=$2

    log_pad $depth
    echo "Error: $message" >> $write_directory$log_file
}

log_warn() {
    local message=$1
    local depth=$2

    log_pad $depth
    echo "Warning: $message" >> $write_directory$log_file
}

log_out() {
    local message=$1
    local depth=$2

    log_pad $depth
    echo "$message" >> $write_directory$log_file
}

log_pad() {
    local -i depth=$1

    if [[ $depth -gt 0 ]] ; then
        printf "%${depth}s" " " >> $write_directory$log_file
    fi
}

log_pad() {
    local -i depth=$1

    if [[ $depth -gt 0 ]] ; then
        printf "%${depth}s" " " >> $write_directory$log_file
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
    echo_out_e "${c_t}DSpace SAF Find Problematic PDFs$c_r"
    echo_out
    echo_out_e "Given a ${c_n}source directory${c_r}, this perform validation on PDFs on all top-level sub-directories."
    echo_out
    echo_out_e "Each of the top-level sub-directories must have a '${c_n}contents${c_r}' file."
    echo_out
    echo_out_e "The PDFs will be validated to be of the correct mime-type 'application/pdf'."
    echo_out_e "Duplicate PDFs within a sub-directory will be reported."
    echo_out_e "Only PDFs specified in the 'contents' file are processed."
    echo_out
    echo_out_e "${c_h}Usage:$c_r"
    echo_out_e "  $c_i$script_pathname$c_r ${c_n}[${c_r}options${c_n}]${c_r} ${c_n}<${c_r}source directory${c_n}>${c_r}"
    echo_out
    echo_out_e "${c_h}Options:$c_r"
    echo_out_e " -${c_i}c${c_r}, --${c_i}checksum${c_r}         Specify a custom checksum utility (currently: '$c_n$checksum_command$c_r')."
    echo_out_e " -${c_i}h${c_r}, --${c_i}help${c_r}             Print this help screen."
    echo_out_e "     --${c_i}legacy${c_r}           Enable compatibility mode with legacy software versions, such as Bash 3.x."
    echo_out_e " -${c_i}l${c_r}, --${c_i}log_file${c_r}         Specify a custom log file name (currently: '$c_n$log_file$c_r')."
    echo_out_e " -${c_i}n${c_r}, --${c_i}no_color${c_r}         Do not apply color changes when printing output to screen."
    echo_out_e " -${c_i}P${c_r}, --${c_i}progress${c_r}         Display progress instead of normal output."
    echo_out_e " -${c_i}s${c_r}, --${c_i}silent${c_r}           Do not print to the screen."
    echo_out_e " -${c_i}V${c_r}, --${c_i}validate${c_r}         Do not perform renaming, only validate mapping file."
    echo_out_e " -${c_i}w${c_r}, --${c_i}write_directory${c_r}  Write log and checksums within this directory (currently: '$c_n$write_directory$c_r')."
    echo_out
    echo_out_e "Warning: ${c_i}legacy${c_r} mode is not guaranteed to work as it only has workarounds for known issues."
    echo_out
}

main "$@"

unset main
unset process_directories
unset validate_pdfs
unset parse_checksum
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
