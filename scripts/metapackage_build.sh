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

# ------------------------------------------------------------------------
# Actual program starts after this
# ------------------------------------------------------------------------

$METAPKG_CHECK_REQD_PKGS_SCRIPT || exit 1
if [ "$DISABLE_GPG_PASSPHRASE_CACHING" = "yes" ] ;then
    echo "INFO:                    You will have to enter your passphrase TWICE"
else
    echo "INFO:                    You may have to enter your passphrase at least once"
fi
echo ""
metapkg_set_vars
metapkg_check_input_files

metapkg_build_debs "image" "$METAPKG_I_DEB"
metapkg_build_debs "headers" "$METAPKG_H_DEB"
metapkg_build_src_debs "image" "$METAPKG_I_SRC"
metapkg_build_src_debs "headers" "$METAPKG_H_SRC"
echo ""
