#!/bin/bash

# script to visit each subdirectory and, if a dublin_core.xml is found, add a element.qualifier with a value
#!/bin/bash

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -e|--element)
    ELEMENT="$2"
    shift # past argument
    shift # past value
    ;;
    -q|--qualifier)
    QUALIFIER="$2"
    shift # past argument
    shift # past value
    ;;
    -v|--value)
    VALUE="$2"
    shift # past argument
    shift # past value
    ;;
#    --default)
#    DEFAULT=YES
#    shift # past argument
#    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

echo ELEMENT = "${ELEMENT}"
echo QUALIFIER = "${QUALIFIER}"
echo VALUE = "${VALUE}"

if [[ -z $QUALIFIER ]]; then
    QUALIFIER="none"
fi

if [[ -n $1 ]]; then
    echo "Last line of file specified as non-opt/last argument:"
    tail -1 "$1"
fi 

REPLACE="s|</dublin_core>|  <dcvalue element=\"$ELEMENT\" qualifier=\"$QUALIFIER\" language=\"en\">$VALUE</dcvalue>\\
</dublin_core>|"

    
# For each directory here.
directories=$(find . -type d -maxdepth 1)
for directory in $directories ; do
    sed -e "$REPLACE" $directory/dublin_core.xml
done