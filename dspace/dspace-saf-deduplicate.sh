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
# depends on the following userspace commands:
#   dirname, file, grep, sed, md5sum (or compatible, like shasum)

main(){
  local script_pathname=$0
  local get_help=
  local no_color=
  local -i i=0
  local parameter=
  local -i parameters_total=$#
  local source_directory=
  local extra_parameters=
  local -i extra_parameters_total=0
  local checksum_command="md5sum"
  local change_log="changes.log"
  local document_name_prefix="document-"
  local contents_file="contents"
  local bundle_name="$(echo -e "\tbundle:ORIGINAL")"
  local -i preserve=0
  local grab_next=

  if [[ $(type -p date) ]] ; then
    change_log="changes-$(date +'%Y_%m_%d').log"
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
        elif [[ $source_directory == "" ]] ; then
          source_directory="$parameter"
        else
          extra_parameters[${extra_parameters_total}]=$parameter
          let extra_parameters_total++
        fi
      else
        if [[ $grab_next == "-c" || $grab_next == "--checksum" ]] ; then
          checksum_command="$parameter"
          grab_next=
        elif [[ $grab_next == "-l" || $grab_next == "--log_file" ]] ; then
          change_log="$parameter"
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

  if [[ $grab_next != "" ]] ; then
    echo
    echo_error "missing parameter for '$c_n$grab_next$c_e'"
    echo
    return
  elif [[ $(echo "$checksum_command" | grep -o "^[[:space:]]*-") != "" || $(type -p "$checksum_command") == "" ]] ; then
    echo
    echo_error "invalid checksum program '$c_n$checksum_command$c_e'"
    echo
    return
  elif [[ $extra_parameters_total -gt 0 ]] ; then
    let i=0
    echo
    local custom_message="only one source directory may be specified at a time, you specified '$c_n$source_directory$c_e'"
    while [[ $i -lt $extra_parameters_total ]] ; do
      parameter=${extra_parameters[i]}
      custom_message="$custom_message, '$c_n$parameter$c_e'"
      let i++
    done
    echo_error "$custom_message."
    echo

    return
  fi

  if [[ $get_help -eq 1 || $i -eq 0 ]] ; then
    print_help
  else
    if [[ ! -r $source_directory ]] ; then
      echo
      echo_error "The source directory '$c_n$source_directory$c_e' not found or not readable."
      echo
      return
    fi

    if [[ ! -d $source_directory ]] ; then
      echo
      echo_error "The source directory '$c_n$source_directory$c_e' not a valid directory."
      echo
      return
    fi

    if [[ ! -x $source_directory ]] ; then
      echo
      echo_error "The source directory '$c_n$source_directory$c_e' not executable."
      echo
      return
    fi

    process_content
  fi
}

print_help() {
  echo
  echo -e "${c_t}DSpace SAF Import De-Duplicator$c_r"
  echo
  echo -e "Given a ${c_n}source directory${c_r}, this remove duplicates and rename all files specified by '$c_n$contents_file$c_r' files found within the source directory."
  echo
  echo -e "${c_h}Usage:$c_r"
  echo -e "  $c_i$script_pathname$c_r ${c_n}[${c_r}options${c_n}]${c_r} ${c_n}<${c_r}source directory${c_n}>${c_r}"
  echo
  echo -e "${c_h}Options:$c_r"
  echo -e " -${c_i}c${c_r}, --${c_i}checksum${c_r}   Specify a custom checksum utility (currently: '$c_n$checksum_command$c_r')."
  echo -e " -${c_i}h${c_r}, --${c_i}help${c_r}       Print this help screen."
  echo -e " -${c_i}l${c_r}, --${c_i}log_file${c_r}   Specify a custom log file name (currently: '$c_n$change_log$c_r')."
  echo -e " -${c_i}n${c_r}, --${c_i}no_color${c_r}   Do not apply color changes when printing output to screen."
  echo -e " -${c_i}p${c_r}, --${c_i}preserve${c_r}   Preserve the original file names instead of renaming."
  echo -e " -${c_i}r${c_r}, --${c_i}rename_to${c_r}  Specify a custom rename to filename prefix (currently: '$c_n$document_name_prefix$c_r')."
  echo
  echo -e "When --${c_i}preserve${c_r} is used, --${c_i}rename_to${c_r} is ignored."
  echo
}

process_content() {
  local file=
  local files=$(find $source_directory -type f -name $contents_file)
  local file_path=

  if [[ $files == "" ]] ; then
    echo
    echo_error "Did not find any files named '$c_n$contents_file$c_e' inside of the directory '$c_n$source_directory$c_e'."
    echo
    return
  fi

  for file in $files ; do
    echo
    echo -e "${c_t}Now Proccessing Set:$c_r $c_n$file$c_r"

    log_out
    log_out "===== Begin Set: '$file' ====="

    file_path=$(dirname $file)

    if [[ $file_path == "" ]] ; then
      echo
      echo_warn "Failed to process directory path for '$c_n$file$c_w', skipping set." 2
      continue
    fi

    if [[ ! -w $file_path ]] ; then
      echo
      echo_warn "The directory path '$c_n$file_path$c_w' is not writable, skipping set." 2
      continue
    fi

    file_path=${file_path}/

    process_documents

    echo -e "  ${c_n}Done$c_r"
  done
}

process_documents() {
  local document=
  local documents=$(grep -o '^document-[[:digit:]]*\.pdf\>' $file)
  local checksum=
  local -A checksums=
  local -A checksums_order=
  local -A checksums_all=

  # remove auto-added index of 0.
  unset checksums[0]
  unset checksums_all[0]

  if [[ $documents == "" ]] ; then
    echo
    echo_warn "No documents described in '$c_n$file$c_w', skipping set." 2
    echo
    log_warn "No documents found in '$file', skipping set."
    return
  fi

  for document in $documents ; do
    if [[ ! -r $file_path$document ]] ; then
      echo
      echo_error "Document '$c_n$file_path$document$c_e' not found or not readable, skipping set." 2
      echo
      log_error "Not found or readable document '$file_path$document', skipping set."
      return
    fi

    if [[ ! -w $file_path$document ]] ; then
      echo
      echo_error "Document '$c_n$file_path$document$c_e' not writable, skipping set." 2
      echo
      log_error "Not writable document '$file_path$document', skipping set."
      return
    fi

    echo -e "  Generating checksum for '$c_h$file_path$document$c_r'."
    checksum=$($checksum_command $file_path$document)

    if [[ $? -ne 0 ]] ; then
      echo
      echo_error "Checksum generation for '$c_n$file_path$document$c_e' failed, skipping set." 2
      echo
      log_error "Checksums generation failed for document '$file_path$document', skipping set."
      return
    fi

    checksum=$(echo $checksum | sed -e 's|[[:space:]][[:space:]]*[^[:space:]].*$||')
    if [[ $checksum == "" ]] ; then
      echo
      echo_error "Failed to process checksum results for '$c_n$file_path$document$c_e', skipping set." 2
      echo
      log_error "Process checksum failed for document '$file_path$document', skipping set."
      return
    fi

    if [[ ${checksums[$checksum]} == "" ]] ; then
      echo -e "    Checksum: (new)       '$c_i$checksum$c_r'."
      log_out "New checksum found '$checksum', document '$file_path$document'."
      checksums[$checksum]="$document";

      # array order is not guaranteed.
      # to attempt to preserve document order, store the index id based on the total checksums in the set.
      checksums_order[$checksum]=${#checksums[*]};
    else
      echo -e "    Checksum: (duplicate) '$c_i$checksum$c_r'."
      log_out "Duplicate checksum found '$checksum', document '$file_path$document'."
    fi

    checksums_all[$document]="$checksum"

    echo
  done

  rename_documents_to_checksum

  if [[ $? -eq 0 ]] ; then
    rename_checksums_to_document
  fi

  if [[ $? -eq 0 ]] ; then
    rebuild_contents_file
  fi
}

rename_documents_to_checksum() {
  local -i i=0
  local -i total=${#checksums_all[*]}
  local file_name_old=
  local file_name_new=
  local extension=
  local checksum=
  local -i failure=0

  if [[ $total -eq 0 ]] ; then
    return 0
  fi

  # renaming files to their checksum name will effectively result in duplicate files being removed.
  for file_name_old in ${!checksums_all[*]} ; do
    checksum=${checksums_all[$file_name_old]}
    extension=$(echo $file_name_old | grep -o '\.[^.]*$')
    file_name_new=$checksum$extension

    mv $file_path$file_name_old $file_path$file_name_new

    if [[ $? -ne 0 ]] ; then
      echo
      echo_error "Something went wrong while moving '$c_n$file_path$file_name_old$c_e' to '$c_n$file_path$file_name_new$c_e'." 6
      echo
      log_error "Failed to move '$file_path$file_name_old' to '$file_path$file_name_new'."
      break
    else
      log_out "Renamed '$file_path$file_name_old' to '$file_path$file_name_new'."
    fi
  done

  for file_name_old in ${!checksums_all[*]} ; do
    if [[ -e $file_path$file_name_old ]] ; then
      echo
      echo_error "File '$c_n$file_path$file_name_old$c_e' not renamed, resetting changes to entire set." 4
      echo
      log_error "File not renamed '$file_path$file_name_old', resetting changes to entire set."
      let failure=1
      break
    fi
  done

  if [[ $failure -eq 1 ]] ; then
    local file_to_delete=
    local files_to_delete=
    local -i revert_failure=0

    for file_name_old in ${!checksums_all[*]} ; do
      checksum=${checksums_all[$file_name_old]}
      extension=$(echo $file_name_old | grep -o '\.[^.]*$')
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
            echo
            echo_warn "Something went wrong while deleting '$c_n$file_path$file_to_delete$c_w'." 6
            echo
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

  for checksum in ${!checksums[*]} ; do
    file_name_old=${checksums[$checksum]}
    extension=$(echo $file_name_old | grep -o '\.[^.]*$')
    file_name_checksum=$checksum$extension

    if [[ $preserve -eq 0 ]] ; then
      order=${checksums_order[$checksum]}
      file_name_desired=$document_name_prefix$order$extension
    else
      file_name_desired=$file_name_old
    fi

    mv $file_path$file_name_checksum $file_path$file_name_desired

    if [[ $? -ne 0 ]] ; then
      echo
      echo_error "Something went wrong while moving '$c_n$file_path$file_name_checksum$c_e' to '$c_n$file_path$file_name_desired$c_e'." 6
      echo
      log_error "Attempted but failed to move '$file_path$file_name_checksum' to '$file_path$file_name_desired'."
      return 1
    else
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
      echo
      echo_warn "Something went wrong while deleting '$c_n$file_path$contents_file$c_w'." 6
      echo
      log_warn "Failed to delete unnecessary '$file_path$contents_file'."
      let failure=1
    else
      log_out "Deleted unnecessary '$file_path$contents_file' (no files to upload)."
    fi

    return $failure
  fi

  echo -n > $file_path$contents_file

  if [[ $? -ne 0 ]] ; then
    echo
    echo_error "Something went wrong while clearing '$c_n$file_path$contents_file$c_e'." 6
    echo
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
      extension=$(echo $file_name | grep -o '\.[^.]*$')
      document_line="$document_name_prefix$i$extension$bundle_name"
    else
      document_line="$file_name$bundle_name"
    fi

    echo "$document_line" >> $file_path$contents_file &&
    echo >> $file_path$contents_file

    if [[ $? -ne 0 ]] ; then
      echo
      echo_error "Something went wrong while appending '$c_n$document_line$c_e' to '$c_n$file_path$contents_file$c_e'." 6
      echo
      log_error "Failed to append '$document_line' to '$file_path$contents_file'."
      let failure=1
    else
      log_out "Appended '$document_line' to '$file_path$contents_file'."
    fi
  done

  # remove last line from contents file (which is an extra empty line).
  sed -i -e '$d' $file_path$contents_file

  if [[ $? -ne 0 ]] ; then
    echo
    echo_warn "Something went wrong while remove last line from '$c_n$file_path$contents_file$c_w'." 6
    echo
    log_warn "Failed to remove last line from '$file_path$contents_file'."
    let failure=1
  fi

  return $failure
}

log_error() {
  local message=$1
  echo "Error: $message" >> $change_log
}

log_warn() {
  local message=$1
  echo "Warning: $message" >> $change_log
}

log_out() {
  local message=$1
  echo "$message" >> $change_log
}

echo_error() {
  local message=$1

  echo_pad $2
  echo -e "${c_e}ERROR: $message$c_r"
}

echo_warn() {
  local message=$1

  echo_pad $2
  echo -e "${c_w}WARNING: $message$c_r"
}

echo_pad() {
  local -i padding=$1

  if [[ $padding -gt 0 ]] ; then
    printf "%${padding}s" " "
  fi
}

main $*

unset main
unset print_help
unset process_content
unset process_documents
unset rename_documents_to_checksum
unset rename_checksums_to_document
unset rebuild_contents_file
unset log_error
unset log_warn
unset log_out
unset echo_error
unset echo_warn
unset echo_pad
