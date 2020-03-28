#!/bin/bash

# load bash-completion functions
source $(dirname $0)/../../../../resources/bash_completion/concuerror

COMP_WORDS=("$1" "$2")
COMP_CWORD=1

_concuerror ignored "$2" "$1"

echo ${COMPREPLY[@]}
