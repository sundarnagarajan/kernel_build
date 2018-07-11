#!/bin/bash
# Environment variables that should be set
# KERNEL_BUILD_DIR - should come from ~/.kernel_build.config
#        or from caller (patch_and_build_kernel.sh)
#
# Packages that need to be installed:
# Package             Command used
# reprepro            reprepro

# Set this to 'yes' to disable passphrase caching by gpg
DISABLE_GPG_PASSPHRASE_CACHING=no

PROGNAME=$(basename $0)
SCRIPT_DIR=$(readlink -f $(dirname $0))

# Global variables

CHECK_REQD_PKGS_SCRIPT=${SCRIPT_DIR}/local_upload_required_pkgs.sh

# Global vars set in set_vars
# KERNEL_BUILD_DIR
# LOCAL_UPLOAD_BUILD_OUT


disable_gpg_passphrase_caching() {
    if [ "$DISABLE_GPG_PASSPHRASE_CACHING" = "yes" ] ;then
        gpgconf --kill gpg-agent
    fi
}

set_vars() {
    INDENT="    "
    if [ -f ~/.kernel_build.config ]; then
        . ~/.kernel_build.config 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Error sourcing ~/.kernel_build.config"
            exit 1
        fi
    else
        echo "INFO:                    ~/.kernel_build.config not found"
    fi
    if [ -z "$LOCAL_DEB_DISTS" ]; then
        LOCAL_DEB_DISTS=$(lsb_release -c | awk '{print $2}')
    fi

    echo "SCRIPT_DIR:              $SCRIPT_DIR"
    echo "KERNEL_BUILD_DIR:        ${KERNEL_BUILD_DIR:-unset}"
    echo "LOCAL_DEB_REPO_DIR:      ${LOCAL_DEB_REPO_DIR:-unset}"
    echo "LOCAL_DEB_DISTS:         ${LOCAL_DEB_DISTS:-unset}"

    if [ -z "$KERNEL_BUILD_DIR" ]; then
        echo "KERNEL_BUILD_DIR must be set"
        exit 1
    fi
    LOCAL_UPLOAD_BUILD_OUT="${KERNEL_BUILD_DIR}/local_upload.out"
    echo "Build output in:         ${LOCAL_UPLOAD_BUILD_OUT:-unset}"
}

exit_with_msg() {
    # $1: Message
    echo "$1"
    echo "See complete output in $LOCAL_UPLOAD_BUILD_OUT"
    exit 1
}

function do_kernel_upload() {
    cd $KERNEL_BUILD_DIR
    echo ""
    echo "--------- Uploading kernel DEBs to local repository ----------"
    echo "Found following DEB files:"
    echo ""
    ls -1 *.deb | sed -e "s/^/${INDENT}/"
    echo ""

    for dist in $LOCAL_DEB_DISTS
    do
       for deb_file in *.deb
        do
            echo "Adding $deb_file to dist $dist"
            reprepro --basedir $LOCAL_DEB_REPO_DIR includedeb $dist $deb_file >> ${LOCAL_UPLOAD_BUILD_OUT} 2>&1
            if [ $? -ne 0 ]; then
                echo "FAILED: Adding $deb_file to dist $dist - see ${LOCAL_UPLOAD_BUILD_OUT}"
            fi
        done
    done
}

function do_metapkg_upload() {
    cd "$METAPKG_BUILD_DIR"
    echo ""
    echo "--------- Uploading metapackage DEBs to local repository ----------"
    echo "Found following DEB files:"
    echo ""
    ls -1 *.deb | sed -e "s/^/${INDENT}/"
    echo ""

    for dist in $LOCAL_DEB_DISTS
    do
       for deb_file in *.deb
        do
            echo "Adding $deb_file to dist $dist"
            reprepro --basedir $LOCAL_DEB_REPO_DIR includedeb $dist $deb_file >> ${LOCAL_UPLOAD_BUILD_OUT} 2>&1
            if [ $? -ne 0 ]; then
                echo "FAILED: Adding $deb_file to dist $dist - see ${LOCAL_UPLOAD_BUILD_OUT}"
            fi
        done
    done
}

# Actual program starts after this

$CHECK_REQD_PKGS_SCRIPT || exit 1
set_vars
if [ -n "$LOCAL_DEB_REPO_DIR" -a -n "$KERNEL_BUILD_DIR" ]; then
    do_kernel_upload
else
    echo "Either LOCAL_DEB_REPO_DIR or KERNEL_BUILD_DIR not set"
    echo "Not trying local upload of kernel DEBs"
fi
if [ -n "$LOCAL_DEB_REPO_DIR"  -a -n "$METAPKG_BUILD_DIR" ]; then
    do_metapkg_upload
else
    echo "Either LOCAL_DEB_REPO_DIR or METAPKG_BUILD_DIR not set"
    echo "Not trying local upload of metapackage DEBs"
fi
