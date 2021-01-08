#!/bin/bash
# Packages that need to be installed:
# Package             Command used
# reprepro            reprepro

if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
SCRIPT_DIR="${PROG_DIR}"

. ${SCRIPT_DIR}/build_kernel_functions.sh 1>/dev/null 2>&1 || exit 1

# ------------------------------------------------------------------------
# Actual program starts after this
# ------------------------------------------------------------------------

$LOCAL_UPLOAD_CHECK_REQD_PKGS_SCRIPT || exit 1
local_upload_set_vars

echo ""
echo "------------------- Signing source packages --------------------"
echo "You will have to enter your passphrase for signing metapackages"
echo "Press RETURN to continue"
echo "----------------------------------------------------------------"
echo ""
read ___a

if [ -n "$LOCAL_DEB_REPO_DIR" -a -n "$KERNEL_BUILD_DIR" ]; then
    local_upload_do_kernel_upload
else
    echo "Either LOCAL_DEB_REPO_DIR or KERNEL_BUILD_DIR not set"
    echo "Not trying local upload of kernel DEBs"
fi
if [ -n "$LOCAL_DEB_REPO_DIR"  -a -n "$METAPKG_BUILD_DIR" ]; then
    local_upload_do_metapkg_upload
else
    echo "Either LOCAL_DEB_REPO_DIR or METAPKG_BUILD_DIR not set"
    echo "Not trying local upload of metapackage DEBs"
fi
