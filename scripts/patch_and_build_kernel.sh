#!/bin/bash

if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
SCRIPT_DIR="${PROG_DIR}"

. ${SCRIPT_DIR}/build_kernel_functions.sh || exit 1

create_dirs || exit 1
# Need 3 GB
check_avail_disk_space 3000000000 $KB_TOP_DIR || exit 1

can_build_metapackage_first
if [ $? -eq 0 ]; then
    build_metapackages || exit 1
    get_kernel_source || exit 1
else
    get_kernel_source || exit 1
    KERN_VER=$(kernel_version $BUILD_DIR) || exit 1
    build_metapackages || exit 1
fi

apply_patches || exit 1
restore_kernel_config || exit 1
build_kernel || exit 1
do_local_upload
