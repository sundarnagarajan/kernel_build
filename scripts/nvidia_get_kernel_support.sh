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
LATEST_DRIVER_URL="https://www.nvidia.com/object/unix.html"
# DRIVER_SELECTOR is applied using grep - FIRST matching line
DRIVER_SELECTOR="Latest Long Lived Branch Version"
DRIVER_PAGE_URL_PREFIX="https:"
# KERNEL_UPDATE_SELECTOR_REGEX is a Regex
KERNEL_UPDATE_SELECTOR_REGEX="Linux [kK]ernel \d+\.\d+"
KERNEL_SELECTOR_REGEX_NOVER='Linux [kK]ernel'
LATEST_KVER_SCRIPT=${SCRIPT_DIR}/latest_major_kernel_version.py


function uninstall_current_driver() {
    return 0
}

function download_driver_version() {
    # $1: version.number
    # $2: output file
    return 0
}

function install_nvidia_driver() {
    # $1: Download .run file
    return 0
}

function get_installed_nvidia_version() {
    # Outputs version number or ''
    # Returns status code of nvidia-smi
    # Returns 200 if nvidia-smi is not found in path
    which nvidia-smi 1>/dev/null 2>&1
    ret=$?
    if [ $ret -ne 0 ]; then
        return 200
    fi
    local nvidia_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
    ret=$?
    echo "$nvidia_ver"
    return $ret
}

function get_latest_driver_version() {
    curl -s "$LATEST_DRIVER_URL" | grep "$DRIVER_SELECTOR" | head -1 | perl -Wnl -e "/href=\".*?\">(.*?)<\/A>/ and print \$1"
}


function get_driver_page_url() {
    curl -s "$LATEST_DRIVER_URL" | grep "$DRIVER_SELECTOR" | head -1 | perl -Wnl -e "/href=\"(.*?)\"/ and print \"${DRIVER_PAGE_URL_PREFIX}\${1}\"" 2>/dev/null
}

function get_kernel_update_changes() {
    # $1: driver_page_url as returned by get_driver_page_url()
    # $2: Kernel version or ""
    local url="$1"
    local kver=$2
    links -width 400 -dump "$url" | grep --color -P "$KERNEL_UPDATE_SELECTOR_REGEX"

    if [ -n "$kver" ]; then
        links -width 400 -dump "$url" | grep --color -P "$KERNEL_SELECTOR_REGEX_NOVER $kver"
    else
        links -width 400 -dump "$url" | grep --color -P "$KERNEL_SELECTOR_REGEX"
    fi

    return $?   # Whether grep matched
}


# ------------------------------------------------------------------------
# Actual script starts after this
# ------------------------------------------------------------------------
driver_page_url=$(get_driver_page_url)
nvidia_installed_ver=$(get_installed_nvidia_version)
if [ -z "$nvidia_installed_ver" ]; then
    nvidia_installed_ver="None"
fi
kver_latest="$($LATEST_KVER_SCRIPT)"

echo "Latest kernel version:    $kver_latest"
echo "Installed nvidia version: $nvidia_installed_ver"
echo "Latest nvidia version:    $(get_latest_driver_version)"
echo "Kernel update-related lines:"
get_kernel_update_changes "$driver_page_url" "$kver_latest"
ret_grep_matched=$?
exit $ret_grep_matched  # Whether KERNEL_UPDATE_SELECTOR_REGEX matched
