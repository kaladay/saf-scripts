#!/bin/bash
#
# Remove problematic PDFs using results from saf-dspace-find_problematic_pdfs.sh script.
#
# This process all files with the extension ".duplicates" within the top-level of the specified problems directory.
# This does not recursively search through sub-directories.
#
# Duplicate files found within the given source directory are removed.
# The filename of the duplicates file (such as '2' from '2.duplicates') represents the directory name at the top-level of the source directory.
#
# Example Usage:
#   ```
#   saf-dspace-remove_problematic_pdfs.sh source_directory problems_directory
#   ```
#
# depends on the following userspace commands:
#   basename, bash, date (optional), find, sed, and touch (optional).

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
    local problems_directory=
    local source_directory=
    local write_directory=$(echo $PWD | sed -e 's|//*|/|g' -e 's|/*$|/|')
    local contents_file="contents"
    local bundle_name="bundle:ORIGINAL"
    local -i update_contents_file=1
    local -i problematic_processed=0
    local -i process_duplicates=1
    local -i process_invalid=1
    local -i process_missing=1

    # logging
    local log_file="changes.log"

    # commands
    local find_command="find"

    if [[ $(type -p date) ]] ; then
        log_file="analysis-$(date +'%Y_%m_%d').log"

        start_stamp=$(date +'%Y/%m/%d %_I:%M:%S %P %z')
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
                if [[ $parameter == "-h" || $parameter == "--help" ]] ; then
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
                elif [[ $parameter == "-u" || $parameter == "--update_contents_file" ]] ; then
                    let update_contents_file=1
                elif [[ $parameter == "-U" || $parameter == "--ignore_contents_file" ]] ; then
                    let update_contents_file=0
                elif [[ $parameter == "-w" || $parameter == "--write_directory" ]] ; then
                    grab_next="$parameter"
                elif [[ $source_directory == "" ]] ; then
                    source_directory=$(echo $parameter | sed -e 's|//*|/|g' -e 's|/*$|/|')
                elif [[ $problems_directory == "" ]] ; then
                    problems_directory=$(echo $parameter | sed -e 's|//*|/|g' -e 's|/*$|/|')
                else
                    extra_parameters[${extra_parameters_total}]="$parameter"
                    let extra_parameters_total++
                fi
            else
                if [[ $grab_next == "-w" || $grab_next == "--write_directory" ]] ; then
                    write_directory=$(echo "$parameter" | sed -e 's|//*|/|g' -e 's|/*$|/|')
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
        local custom_message="only one source directory and one duplicates directory may be specified at a time, you specified '$c_n$source_directory$c_e', '$c_n$problems_directory$c_e'"
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

    if [[ $(type -p find) == "" ]] ; then
        echo_out2
        echo_error "Failed to find required (find) command '${c_n}find$c_r'"
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

    if [[ ! -r $problems_directory ]] ; then
        echo_out2
        echo_error "The problems directory '$c_n$problems_directory$c_e' is not found or is not readable."
        echo_out2
        return 1
    fi

    if [[ ! -d $problems_directory ]] ; then
        echo_out2
        echo_error "The problems directory '$c_n$problems_directory$c_e' is not a valid directory."
        echo_out2
        return 1
    fi

    if [[ ! -x $problems_directory ]] ; then
        echo_out2
        echo_error "The problems directory '$c_n$problems_directory$c_e' is not executable."
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

    if [[ $process_duplicates -eq 0 && $process_invalid -eq 0 && $process_missing -eq 0 ]] ; then
        echo_out2
        echo_error "No operations to perform, please enable at least one of the processors: '${c_n}duplicates$c_e', '${c_n}invalid$c_e', or '${c_n}missing$c_e'."
        echo_out2
        return 1
    fi

    remove_problems
    return $?
}

remove_problems() {
    echo_out
    echo_out_e "${c_t}Analyzing Problems Directory:$c_r $c_n$problems_directory$c_r"

    log_out
    if [[ $start_stamp == "" ]] ; then
        log_out "====== Analyzing Problems Directory: '$problems_directory' ======"
    else
        echo_out "Started On: $start_stamp" 2
        log_out "====== Analyzing Problems Directory: '$problems_directory' ($start_stamp) ======"
    fi

    if [[ $process_duplicates -eq 1 ]] ; then
        remove_problem "Duplicate" "duplicates"
        if [[ $? -ne 0 ]] ; then
            return 1
        fi
    fi

    if [[ $process_invalid -eq 1 ]] ; then
        remove_problem "Invalid" "invalid"
        if [[ $? -ne 0 ]] ; then
            return 1
        fi
    fi

    if [[ $process_missing -eq 1 ]] ; then
        remove_missing
        if [[ $? -ne 0 ]] ; then
            return 1
        fi
    fi

    if [[ $problematic_processed -eq 0 ]] ; then
        echo_out2
        echo_warn "No files ending in \"${c_n}.duplicates$c_w\", \"${c_n}.invalid$c_w\", or \"${c_n}.missing$c_w\" found in Problems Directory: '$c_n$problems_directory$c_w'." 2
        echo_out2
        log_warn "No files ending in \".duplicates\",  \".invalid\", or \".missing\" found in Problems Directory: '$problems_directory'." 2
    fi

    return 0
}

remove_problem() {
    local problem_label="$1"
    local problem_extension="$2"
    local index=
    local -i failure=0
    local -a problem_files=()
    local -i problem_files_total=0
    local files=
    local file_name=
    local problem_file=
    local directory=
    local directory_name=

    # build a list of files within the specified problems directory to process.
    for index in $($find_command $problems_directory -nowarn -mindepth 1 -maxdepth 1 -type f -name "*\.$problem_extension") ; do
        problem_files["$problem_files_total"]=$(basename $index | sed -e "s|\.$problem_extension\$||")
        let problem_files_total++
    done

    if [[ $problem_files_total -eq 0 ]] ; then
        return 0
    fi

    let problematic_processed=1

    for index in ${!problem_files[@]} ; do
        directory_name=${problem_files[$index]}
        directory="${directory_name}/"
        problem_file="${directory_name}.$problem_extension"

        echo_out
        echo_out_e "${c_t}Now Processing $problem_label File:$c_r $c_n$problem_file$c_r"

        log_out
        log_out "===== Processing $problem_label File: '$problem_file' ====="

        if [[ ! -d "$source_directory$directory" ]] ; then
            echo_error "Directory not found: '$c_n$directory_name$c_w'." 2
            echo_out2
            log_error "Directory not found: '$source_directory$directory'." 2
            failure=1
            continue
        fi

        files=$(cat $problems_directory$problem_file | sed -e "s|^[[:space:]]*||" -e "s|[[:space:]].*\$||")
        if [[ $files == "" ]] ; then
            echo_warn "Empty $problem_label file: '$c_n$problem_file$c_w'." 2
            echo_out2
            log_warn "Empty $problem_label file: '$problems_directory$problem_file'." 2
            continue
        fi

        for file_name in $files ; do
            if [[ ! -f $source_directory$directory$file_name ]] ; then
                echo_warn "$problem_label file not found: '$c_n$file_name$c_w'." 2
                echo_out2
                log_warn "$problem_label file not found: '$source_directory$directory$file_name'." 2
                continue
            fi

            rm -f $source_directory$directory$file_name
            if [[ $? -ne 0 ]] ; then
                echo_error "Failed to delete $problem_label file: '$c_n$file_name$c_w'." 2
                echo_out2
                log_error "Failed to delete $problem_label file: '$source_directory$directory$file_name'." 2
                let failure=1
                continue
            fi

            echo_out_e "Deleted $problem_label file: '$c_n$file_name'$c_r" 2
            log_out "Deleted $problem_label file: '$source_directory$directory$file_name'" 2

            if [[ $update_contents_file -eq 1 && -f $source_directory$directory$contents_file ]] ; then
                sed -i -e "/^$file_name[[:space:]][[:space:]]*${bundle_name}[[:space:]]*\$/d" $source_directory$directory$contents_file

                if [[ $? -eq 0 ]] ; then
                    echo_out_e "Updated contents file: '$c_n$contents_file'$c_r" 4
                    log_out "Updated contents file: '$source_directory$directory$contents_file'" 4

                    sed -i -e ':a;N;$!ba;s/\n\n\n/\n\n/g' $source_directory$directory$contents_file

                    if [[ $? -eq 0 ]] ; then
                        echo_out_e "Removed invalid newlines in contents file: '$c_n$contents_file'$c_r" 4
                        log_out "Removed invalid newlines in contents file: '$source_directory$directory$contents_file'" 4
                    else
                        echo_warn "Failed to remove excess newlines in contents file: '$c_n$contents_file$c_w'." 4
                        log_warn "Failed to remove excess newlines in contents file: '$source_directory$directory$contents_file'." 4
                    fi
                else
                    echo_warn "Failed to update contents file: '$c_n$contents_file$c_w'." 4
                    log_warn "Failed to update contents file: '$source_directory$directory$contents_file'." 4
                fi

                echo_out
            fi
        done
    done

    return $failure
}

remove_missing() {
    if [[ $update_contents_file -eq 0 ]] ; then
        return 0
    fi

    local index=
    local -i failure=0
    local -a missing_files=()
    local -i missing_files_total=0
    local files=
    local file_name=
    local missing_file=
    local directory=
    local directory_name=

    # build a list of files within the specified problems directory to process.
    for index in $($find_command $problems_directory -nowarn -mindepth 1 -maxdepth 1 -type f -name '*\.missing') ; do
        missing_files["$missing_files_total"]=$(basename $index | sed -e 's|\.missing$||')
        let missing_files_total++
    done

    if [[ $missing_files_total -eq 0 ]] ; then
        return 0
    fi

    let problematic_processed=1

    for index in ${!missing_files[@]} ; do
        directory_name=${missing_files[$index]}
        directory="${directory_name}/"
        missing_file="${directory_name}.missing"

        echo_out
        echo_out_e "${c_t}Now Processing Missing File:$c_r $c_n$missing_file$c_r"

        log_out
        log_out "===== Processing Missing File: '$missing_file' ====="

        if [[ ! -d "$source_directory$directory" ]] ; then
            echo_error "Directory not found: '$c_n$directory_name$c_w'." 2
            echo_out2
            log_error "Directory not found: '$source_directory$directory'." 2
            failure=1
            continue
        fi

        if [[ ! -f $source_directory$directory$contents_file ]] ; then
            echo_warn "Contents file not found: '$c_n$directory$contents_file$c_w'." 2
            echo_out2
            log_warn "Contents file not found: '$source_directory$directory$contents_file'." 2
            continue
        fi

        files=$(cat $problems_directory$missing_file | sed -e "s|^[[:space:]]*||" -e "s|[[:space:]].*\$||")
        if [[ $files == "" ]] ; then
            echo_warn "Empty missing file: '$c_n$missing_file$c_w'." 2
            echo_out2
            log_warn "Empty missing file: '$problems_directory$missing_file'." 2
            continue
        fi

        for file_name in $files ; do
            echo_out_e "Removing '$c_n$file_name$c_r' from contents file: '$c_n$contents_file'$c_r" 2
            log_out "Removing '$file_name' from contents file: '$source_directory$directory$contents_file'" 2

            sed -i -e "/^$file_name[[:space:]][[:space:]]*${bundle_name}[[:space:]]*\$/d" $source_directory$directory$contents_file

            if [[ $? -eq 0 ]] ; then
                echo_out_e "Updated contents file: '$c_n$contents_file'$c_r" 4
                log_out "Updated contents file: '$source_directory$directory$contents_file'" 4

                sed -i -e ':a;N;$!ba;s/\n\n\n/\n\n/g' $source_directory$directory$contents_file

                if [[ $? -eq 0 ]] ; then
                    echo_out_e "Removed duplicate newlines in contents file: '$c_n$contents_file'$c_r" 4
                    log_out "Removed duplicate newlines in contents file: '$source_directory$directory$contents_file'" 4
                else
                    echo_warn "Failed to remove excess newlines in contents file: '$c_n$contents_file$c_w'." 4
                    log_warn "Failed to remove excess newlines in contents file: '$source_directory$directory$contents_file'." 4
                fi
            else
                echo_warn "Failed to update contents file: '$c_n$contents_file$c_w'." 4
                log_warn "Failed to update contents file: '$source_directory$directory$contents_file'." 4
            fi

            echo_out
        done
    done

    return $failure
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
    echo_out
    echo_out_e "${c_t}DSpace SAF Remove Duplicate PDFs$c_r"
    echo_out
    echo_out_e "Given a ${c_n}source directory${c_r} and a ${c_n}duplicates directory${c_r}, remove duplicate files."
    echo_out
    echo_out_e "The ${c_n}duplicates directory${c_r} directory should contain files with the extension \".duplicates\"."
    echo_out_e "These \".duplicates\" are generated by the script ${c_n}saf-dspace-find_problematic_pdfs.sh${c_r}."
    echo_out
    echo_out_e "${c_h}Usage:$c_r"
    echo_out_e "  $c_i$script_pathname$c_r ${c_n}[${c_r}options${c_n}]${c_r} ${c_n}<${c_r}source directory${c_n}>${c_r} ${c_n}<${c_r}duplicates directory${c_n}>${c_r}"
    echo_out
    echo_out_e "${c_h}Options:$c_r"
    echo_out_e " -${c_i}h${c_r}, --${c_i}help${c_r}                  Print this help screen."
    echo_out_e "     --${c_i}legacy${c_r}                Enable compatibility mode with legacy software versions, such as Bash 3.x."
    echo_out_e " -${c_i}l${c_r}, --${c_i}log_file${c_r}              Specify a custom log file name (currently: '$c_n$log_file$c_r')."
    echo_out_e " -${c_i}n${c_r}, --${c_i}no_color${c_r}              Do not apply color changes when printing output to screen."
    echo_out_e " -${c_i}P${c_r}, --${c_i}progress${c_r}              Display progress instead of normal output."
    echo_out_e " -${c_i}s${c_r}, --${c_i}silent${c_r}                Do not print to the screen."
    echo_out_e " -${c_i}V${c_r}, --${c_i}validate${c_r}              Do not perform renaming, only validate mapping file."
    echo_out_e " -${c_i}u${c_r}, --${c_i}update_contents_file${c_r}  Enable updating of the contents file after making changes."
    echo_out_e " -${c_i}U${c_r}, --${c_i}ignore_contents_file${c_r}  Disable updating of the contents file after making changes."
    echo_out_e " -${c_i}w${c_r}, --${c_i}write_directory${c_r}       Write logs within this directory (currently: '$c_n$write_directory$c_r')."
    echo_out
    echo_out_e "Warning: ${c_i}legacy${c_r} mode is not guaranteed to work as it only has workarounds for known issues."
    echo_out
}

main "$@"

unset main
unset remove_problems
unset remove_problem
unset remove_missing
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
