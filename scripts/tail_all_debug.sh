#!/bin/bash
if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
SCRIPT_DIR="${PROG_DIR}"

. ${SCRIPT_DIR}/build_kernel_functions.sh 1>/dev/null 2>&1 || exit 1

tail -F "$CHOSEN_OUT_FILEPATH" "$OLDCONFIG_OUT_FILEPATH" "$COMPILE_OUT_FILEPATH" "$METAPKG_BUILD_OUT_FILEPATH" "$LOCAL_UPLOAD_BUILD_OUT_FILEPATH"
