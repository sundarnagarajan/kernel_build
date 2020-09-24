#!/bin/bash

if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
SCRIPT_DIR="${PROG_DIR}"


KERNEL__BUILD_SRC_PKG=no KERNEL__BUILD_META_PACKAGE=no KERNEL__DO_LOCAL_UPLOAD=no ${PROG_DIR}/patch_and_build_kernel.sh
