#!/bin/bash

if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
SCRIPT_DIR="${PROG_DIR}"

CHANGELOG_URL='https://www.virtualbox.org/wiki/Changelog'
# KERNEL_UPDATE_SELECTOR_REGEX is a Regex
KERNEL_SELECTOR_REGEX='Linux \d+\.\d+'
KERNEL_SELECTOR_REGEX_NOVER='Linux'
LATEST_KVER_SCRIPT=${SCRIPT_DIR}/latest_major_kernel_version.py


function install_latest_version() {
    # $1: version.number
    return 0
}

function get_available_versions() {
    dpkg -l virtualbox-* | sed -e '1,5d' | awk '{print $2}' | grep -P '^virtualbox-\d+\.\d+' | perl -Wnl -e '/-(\d+\.\d+)/ and print $1'
}

function get_installed_versions() {
    dpkg -l virtualbox-* | sed -e '1,5d' | grep '^ii' | awk '{print $2}' | grep -P '^virtualbox-\d+\.\d+' | perl -Wnl -e '/-(\d+\.\d+)/ and print $1'
}

function get_kernel_update_changes() {
    # $1: Virtualbox version
    # $2: Kernel version or ""
    local ver=$1
    local kver=$2
    local url="$CHANGELOG_URL"
    if [ -n "$ver" ]; then
        url="${url}-${ver}"
    fi

    if [ -n "$kver" ]; then
        links -width 400 -dump "$url" | grep -vP '^\s+$' | sed -e "s/^/Virtualbox ${ver}: /" | grep 'Linux host' | grep --color -P "$KERNEL_SELECTOR_REGEX_NOVER $kver"
    else
        links -width 400 -dump "$url" | grep -vP '^\s+$' | sed -e "s/^/Virtualbox ${ver}: /" | grep 'Linux host' | grep --color -P "$KERNEL_SELECTOR_REGEX"
    fi
}

function find_ver_supporting_kver() {
    # $1: kernel version.number
    # Outputs selected line from changelog of versions with changes for kernel version.number

    local kver=$1
    for v in $(echo -e "$AVAILABLE_VERSIONS")
    do
       if [ "$AVAILABLE_VERSIONS" = "$INSTALLED_VERSION" ]; then
           continue
       fi
       get_kernel_update_changes $v $kver
    done
}


# ------------------------------------------------------------------------
# Actual script starts after this
# ------------------------------------------------------------------------

AVAILABLE_VERSIONS="$(get_available_versions)"
INSTALLED_VERSION="$(get_installed_versions)"
LATEST_VERSION="$(echo -e "${AVAILABLE_VERSIONS}\n${INSTALLED_VERSION}" | sort -Vr | head -1)"

kver_latest=$($LATEST_KVER_SCRIPT)
echo "Latest kernel version:        $kver_latest"

if [ -n "$AVAILABLE_VERSIONS" ]; then
    echo "Virtualbox Available versions:"
    echo -e "$AVAILABLE_VERSIONS" | sort -Vr | sed -e 's/^/    /'
fi
if [ -n "$INSTALLED_VERSION" ]; then
    echo "Virtualbox installed version: $INSTALLED_VERSION"
fi

if [ -n "$AVAILABLE_VERSIONS" ]; then
    echo -e "Virtualbox latest version:    $LATEST_VERSION"
fi

if [ -n "$INSTALLED_VERSION" -a -n "$LATEST_VERSION" ]; then
    if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        echo "Already using latest Virtualbox version"
    fi
fi

find_ver_supporting_kver $kver_latest
