#!/bin/bash

main() {
  local pdf=$1
  #For linux, use -i:
  #local mime=$(file -b -i "$pdf" | sed -e 's|;.*$||')
  #For OS X use -I:
  local mime=$(file -b -I "$pdf" | sed -e 's|;.*$||')
  local result=1

  echo "Mime of '$pdf' = $mime"

  if [[ $mime == "application/pdf" ]] ; then
    result=0
  fi

  return $result;
}

main "$1"
