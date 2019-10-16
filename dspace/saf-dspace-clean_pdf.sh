#!/bin/bash

main() {
  local pdf=$1
  local newname=$2
  local destination=$3
  local filename=
  local directory=
  local mime=$(file -b -i "$pdf" | sed -e 's|;.*$||')
  local result=

  echo "Mime of '$pdf' = $mime"
  if [[ $mime == "application/pdf" ]] ; then
    return 0
  fi

  filename=$(basename $pdf)
  directory=$(echo $pdf | sed -e "s|$filename$||")

  rm -vf $pdf
  result=$?
  if [[ $result -ne 0 ]] ; then
    return $result
  fi

  filename=$(basename $directory)

  mv -v $directory $destination/$newname-$filename
  result=$?
  if [[ $result -ne 0 ]] ; then
    return $result
  fi

  return 0
}

main "$1" "$2" "$3"
