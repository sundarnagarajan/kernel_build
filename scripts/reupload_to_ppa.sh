#!/bin/bash
# ------------------------------------------------------------------------
# This script automatically rebuilds the linux kernel source package
# with an incremented version so that upload to launchpad PPA
# can be attempted again if previous upload failed
# ------------------------------------------------------------------------
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

$PPA_UPLOAD_CHECK_REQD_PKGS_SCRIPT || exit 1
reupload_set_vars || exit 1
reupload_rebuild_src_pkg "$@"

ppa_upload_set_vars
ppa_upload_check_deb_dir || exit 1


echo ""
echo "------------------- Signing source packages --------------------"
echo "You will have to enter your passphrase for signing metapackages"
echo "Press RETURN to continue"
echo "----------------------------------------------------------------"
echo ""
read ___a

reupload_upload_src_to_ppa

echo "-------------------------- PPA upload time -----------------------------------"
cat $START_END_TIME_FILEPATH
echo "------------------------------------------------------------------------------"
