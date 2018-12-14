#!/bin/bash
# ------------------------------------------------------------------------
# This script changes $(pwd)/debian/changelog - expects to be in kernel
# source directory ($BUILD_DIR)
# ------------------------------------------------------------------------
if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
SCRIPT_DIR="${PROG_DIR}"

# . ${SCRIPT_DIR}/build_kernel_functions.sh 1>/dev/null 2>&1 || exit 1

if [ ! -f debian/changelog ]; then
    echo "changelog not found $(pwd)/debian/changelog"
    echo "This script should be called from kernel source directory"
    echo "Not attemptiong to write changelog"
    echo "DEBUG: CWD: $(pwd)"
    ls -lR
    exit 0
fi

echo "Writing changelog"
dch -a "Starting with upstream from kernel.org, specific patches are applied to support Intel CherryTrail platform."
dch -a "No out-of-tree modules are used"
dch -a "Patch filenames ending in .optional are attempted but optional"
dch -a "Find list of patches at https://github.com/sundarnagarajan/kernel_build/tree/master/patches"
dch -a ""
dch -a "Following values were explicitly set in .config:"
cat $SCRIPT_DIR/../config/config.prefs | grep -v '^#' | sed -e 's/^/    /' | while IFS='' read -r a ; do dch -a "$a"; done
