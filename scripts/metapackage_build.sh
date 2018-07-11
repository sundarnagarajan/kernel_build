#!/bin/bash
# Environment variables that should be set
# DEBEMAIL - should come from ~/.kernel_build.config
#        or from caller (patch_and_build_kernel.sh)
# DEBFULLNAME - should come from ~/.kernel_build.config
#        or from caller (patch_and_build_kernel.sh)
#        - defaults to user's full name from /etc/passwd
#          However, with the default, gpg signing MAY fail
# META_PKGNAME_PREFIX - defaults to 'cherrytux'
# KERNEL_VERSION - should come from caller (patch_and_build_kernel.sh)
# METAPKG_BUILD_DIR - should come from ~/.kernel_build.config
#        or from caller (patch_and_build_kernel.sh)
#
# Packages that need to be installed:
# Package             Command used
# equivs:             equivs-build
# dh-make:            dh_make
# dpkg-dev:           dpkg-buildpackage

# Set this to 'yes' to disable passphrase caching by gpg
DISABLE_GPG_PASSPHRASE_CACHING=no
LICENSE=gpl2 # for dh_make

PROGNAME=$(basename $0)
SCRIPT_DIR=$(readlink -f $(dirname $0))

# Global variables
INPUT_FILE_DIR=$(readlink -f ${SCRIPT_DIR}/../config/metapkg_controlfile_templates)
I_DEB=i_deb
I_SRC=i_src
H_DEB=h_deb
H_SRC=h_src
# Tokens replaced in I_DEB, ISRC, H_DEB, H_SRC
TOKEN_VERSION="__VERSION__"
TOKEN_PREFIX="__PKG_PREFIX__"
TOKEN_MAINTAINER="__MAINTAINER__"

CHECK_REQD_PKGS_SCRIPT=${SCRIPT_DIR}/metapackage_required_pkgs.sh

# Global vars set in set_vars
# DEBEMAIL
# DEBFULLNAME
# KERNEL_VERSION
# METAPKG_BUILD_DIR
# META_PKGNAME_PREFIX
# MAINTAINER
# METAPKG_BUILD_OUT


disable_gpg_passphrase_caching() {
    if [ "$DISABLE_GPG_PASSPHRASE_CACHING" = "yes" ] ;then
        gpgconf --kill gpg-agent
    fi
}

set_vars() {
    if [ -f ~/.kernel_build.config ]; then
        . ~/.kernel_build.config 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Error sourcing ~/.kernel_build.config"
            exit 1
        fi
    else
        echo "INFO:                    ~/.kernel_build.config not found"
    fi

    DEBFULLNAME=${DEBFULLNAME:-$(getent passwd $USER | cut -d: -f5 | cut -d, -f1)}
    META_PKGNAME_PREFIX=${META_PKGNAME_PREFIX:-cherrytux}

    echo "SCRIPT_DIR:              $SCRIPT_DIR"
    echo "INPUT_FILE_DIR:          $INPUT_FILE_DIR"
    echo "DEBEMAIL:                ${DEBEMAIL:-unset}"
    echo "DEBFULLNAME:             ${DEBFULLNAME:-unset}"
    echo "KERNEL_VERSION:          ${KERNEL_VERSION:-unset}"
    echo "METAPKG_BUILD_DIR:       ${METAPKG_BUILD_DIR:-unset}"
    echo "META_PKGNAME_PREFIX:     ${META_PKGNAME_PREFIX:-unset}"

    if [ -z "$DEBEMAIL" ]; then
        echo "DEBEMAIL must be set"
        exit 1
    fi
    if [ -z "$KERNEL_VERSION" ]; then
        echo "KERNEL_VERSION must be set"
        exit 1
    fi
    if [ -z "$METAPKG_BUILD_DIR" ]; then
        echo "METAPKG_BUILD_DIR must be set"
        exit 1
    fi
    if [ ! -d "$METAPKG_BUILD_DIR" ]; then
        echo "METAPKG_BUILD_DIR not a directory: $METAPKG_BUILD_DIR"
        exit 1
    fi
    MAINTAINER="${DEBFULLNAME} <${DEBEMAIL}>"
    echo "MAINTAINER:              ${MAINTAINER:-unset}"
    DISTRIBUTION=$(lsb_release -c | awk '{print $2}')
    echo "DISTRIBUTION:            ${DISTRIBUTION:-unset}"
    METAPKG_BUILD_OUT="${METAPKG_BUILD_DIR}/build_meta.out"
    echo "Build output in:         ${METAPKG_BUILD_OUT:-unset}"
}

check_input_files() {
    I_DEB="${INPUT_FILE_DIR}/$I_DEB"
    I_SRC="${INPUT_FILE_DIR}/$I_SRC"
    H_DEB="${INPUT_FILE_DIR}/$H_DEB"
    H_SRC="${INPUT_FILE_DIR}/$H_SRC"

    ERRS=0
    for f in $I_DEB $I_SRC $H_DEB $H_SRC
    do
        if [ ! -f "$f" ]; then
            echo "Missing input file: $f"
            ERRS=1
        fi
    done
    if [ $ERRS -ne 0 ]; then
        exit 1
    fi
}

exit_with_msg() {
    # $1: Message
    echo "$1"
    echo "See complete output in $METAPKG_BUILD_OUT"
    exit 1
}

metapkg_build_debs() {
    # $1: image|headers
    # $2: control file: $I_DEB or $H_DEB

    local PKG_NAME_EXT="$1"
    local PKG_CONTROL_FILE="$2"

    cat "$PKG_CONTROL_FILE" | sed -e "s/${TOKEN_VERSION}/${KERNEL_VERSION}/g" -e "s/${TOKEN_PREFIX}/${META_PKGNAME_PREFIX}/g" -e "s/${TOKEN_MAINTAINER}/${MAINTAINER}/g" > "${METAPKG_BUILD_DIR}/${PKG_NAME_EXT}"
    (cd "${METAPKG_BUILD_DIR}"; equivs-build ${PKG_NAME_EXT} 1>>"$METAPKG_BUILD_OUT" 2>&1 && rm -f "${METAPKG_BUILD_DIR}/${PKG_NAME_EXT}" || exit_with_msg "equivs-build ${PKG_NAME_EXT} failed")
    echo "Binary deb built:        $(ls -1 ${METAPKG_BUILD_DIR}/${META_PKGNAME_PREFIX}-${PKG_NAME_EXT}_${KERNEL_VERSION}_all.deb 2>/dev/null)"
}

metapkg_build_src_debs() {
    # $1: image|headers
    # $2: control file: $I_SRC or $H_SRC

    local PKG_NAME_EXT="$1"
    local PKG_CONTROL_FILE="$2"

    local TEMP_DIR="${METAPKG_BUILD_DIR}/${META_PKGNAME_PREFIX}-${PKG_NAME_EXT}-${KERNEL_VERSION}"
    \rm -rf "${TEMP_DIR}"
    mkdir -p "${TEMP_DIR}"
    cd "$TEMP_DIR"

    dh_make -i -e"$DEBEMAIL" --createorig -c "$LICENSE" --indep -p ${META_PKGNAME_PREFIX}-${PKG_NAME_EXT} -y -n 1>>"$METAPKG_BUILD_OUT" 2>&1 || exit_with_msg "dh_make ${META_PKGNAME_PREFIX}-${PKG_NAME_EXT} failed"
    \rm -f debian/*.ex debian/*.EX debian/README.Debian debian/README.source
    # Fix distribution that is EMBEDDED in changelog!
    sed --in-place "1 s/ unstable;/ ${DISTRIBUTION};/" debian/changelog
    sed --in-place "s/^Version: *$/Version: ${KERNEL_VERSION}/" debian/control
    cat "$PKG_CONTROL_FILE" | sed -e "s/${TOKEN_VERSION}/${KERNEL_VERSION}/g" -e "s/${TOKEN_PREFIX}/${META_PKGNAME_PREFIX}/g" -e "s/${TOKEN_MAINTAINER}/${MAINTAINER}/g" > debian/control

    disable_gpg_passphrase_caching   # depending on DISABLE_GPG_PASSPHRASE_CACHING

    dpkg-buildpackage -S -e"${MAINTAINER}"  -m"${MAINTAINER}" 1>>"$METAPKG_BUILD_OUT" 2>&1 || exit_with_msg "dpkg-buildpackage ${META_PKGNAME_PREFIX}-${PKG_NAME_EXT} failed"

    cd "${SCRIPT_DIR}"
    \rm -rf "${TEMP_DIR}"
    echo "Source deb built:        $(ls -1 ${METAPKG_BUILD_DIR}/${META_PKGNAME_PREFIX}-${PKG_NAME_EXT}_${KERNEL_VERSION}_source.changes 2>/dev/null)"
}




# Actual program starts after this

$CHECK_REQD_PKGS_SCRIPT || exit 1
if [ "$DISABLE_GPG_PASSPHRASE_CACHING" = "yes" ] ;then
    echo "INFO:                    You will have to enter your passphrase TWICE"
else
    echo "INFO:                    You may have to enter your passphrase at least once"
fi
echo ""
set_vars
check_input_files
(cd "${METAPKG_BUILD_DIR}" && rm -rf * )

metapkg_build_debs "image" "$I_DEB"
metapkg_build_debs "headers" "$H_DEB"
metapkg_build_src_debs "image" "$I_SRC"
metapkg_build_src_debs "headers" "$H_SRC"
echo ""
