#!/bin/bash
#-------------------------------------------------------------------------
# Functions for compiling kernel and meta-packages
#-------------------------------------------------------------------------



#-------------------------------------------------------------------------
# Environment variables:
#-------------------------------------------------------------------------
# The following are _THE_ list of environment variables that are used
# if set. These variables (except KERNEL_BUILD_CONFIG) can also be set
# in the config file - by default this is ~/.kernel_build.config, but
# location of config can be overridden by KERNEL_BUILD_CONFIG variable
#
#       --------------------------------------------------------
#       - Config variables override defaults
#       - Environment variables override config variables
#       - Config variables NEVER override environment variables
#       --------------------------------------------------------
#
# See ../docs/env_vars_config.txt for explanation of variables
#
#   KERNEL_BUILD_CONFIG
#   KERNEL_TYPE
#   KERNEL_VERSION
#   KERNEL_SOURCE_URL"
#
# Variables driving which steps are performed:
# -------------------------------------------
#   KERNEL__BUILD_SRC_PKG
#   KERNEL__BUILD_META_PACKAGE
#   KERNEL__DO_LOCAL_UPLOAD
#   KERNEL__APPLY_PATCHES
#
# Variables specifying paths:
# --------------------------
#   KERNEL_BUILD_DIR
#   KERNEL_CONFIG
#   KERNEL_PATCH_DIR
#   KERNEL_CONFIG_PREFS
#
# Variables used in local_upload.sh (ONLY):
# ----------------------------------------
#   LOCAL_DEB_REPO_DIR
#   LOCAL_DEB_DISTS
#
# Variables used in ppa_upload.sh (ONLY):
# --------------------------------------
#   DPUT_PPA_NAME
#   GPG_DEFAULT_KEY_SET
#   GPG_KEYID
#
# Variables used in metapackage_build.sh and ppa_upload.sh:
# --------------------------------------------------------
#   DEBEMAIL
#   DEBFULLNAME
#
# Other variables:
# ---------------
#   NUM_THREADS
#   META_PKGNAME_PREFIX
#   GIT_CLONE_COMMAND
#-------------------------------------------------------------------------

if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
SCRIPT_DIR="${PROG_DIR}"

#-------------------------------------------------------------------------
# Do not allow config (or code) to override environment variables
# The list below is also THE set of config variables that are used
# (except KERNEL_BUILD_CONFIG)
#-------------------------------------------------------------------------
CONFIG_VARS="KERNEL_BUILD_CONFIG DEBEMAIL DEBFULLNAME KERNEL_BUILD_DIR DPUT_PPA_NAME GPG_DEFAULT_KEY_SET KERNEL_TYPE LOCAL_DEB_REPO_DIR LOCAL_DEB_DISTS META_PKGNAME_PREFIX NUM_THREADS GPG_KEYID KERNEL_VERSION KERNEL_CONFIG KERNEL_PATCH_DIR KERNEL_CONFIG_PREFS KERNEL__BUILD_SRC_PKG KERNEL__BUILD_META_PACKAGE KERNEL__DO_LOCAL_UPLOAD KERNEL__APPLY_PATCHES KERNEL_SOURCE_URL GIT_CLONE_COMMAND DISABLE_GPG_PASSPHRASE_CACHING"
readonly CONFIG_VARS
for v in $CONFIG_VARS
do
    if [ -n "${!v}" ]; then readonly $v; fi
done

#-------------------------------------------------------------------------
# Following can be overridden by environment variables
#-------------------------------------------------------------------------
# Config file to customize build variables
# Filename (full path) can be overridden by environment variable
# KERNEL_BUILD_CONFIG
KBUILD_CONFIG=~/.kernel_build.config

# Kernel config file
# Default is ${SCRIPT_DIR}/../config/${CONFIG_FILE}
# Filename (full path) can be overridden by KERNEL_CONFIG env var
CONFIG_FILE=config.kernel

# Patch directory - all patches are expected to be in files in this dir
# Can be overridden by KERNEL_PATCH_DIR env var
# - Each file in directory can contain one or more patches
# - Patches are applied in file (lexicographic order)
# - Patch filenames ending in '.optional' are applied if possible.
#   Failures are ignored
# - Patch filenames NOT ending in '.optional' are considered mandatory.
#   Kernel build FAILS if patch does not apply.
# Default is ${SCRIPT_DIR}/../patches
PATCH_DIR=patches

# Prefs for updating kernel config
CONFIG_PREFS_FILE=config.prefs

#-------------------------------------------------------------------------
# Variables that CANNOT be overridden by environment variables
#-------------------------------------------------------------------------
# Debug outputs - will be created in DEBUG_DIR

# Output of build_kernel (ONLY)
COMPILE_OUT_FILENAME=compile.out
# Output of make oldconfig | silentoldconfig (ONLY)
OLDCONFIG_OUT_FILENAME=oldconfig.out
# Output of ANSWER_QUESTIONS_SCRIPT - answers chosen (ONLY)
CHOSEN_OUT_FILENAME=chosen.out
# File containing time taken for different steps
START_END_TIME_FILE=start_end.out
# Output of metapackage_build.sh
METAPKG_BUILD_OUT="build_meta.out"
# Output of local_upload.sh
LOCAL_UPLOAD_BUILD_OUT="local_upload.out"

# Required scripts - must be in same dir as this script
KERNEL_SOURCE_SCRIPT=get_kernel_source_url.py
SHOW_AVAIL_KERNELS_SCRIPT=show_available_kernels.py
SHOW_CHOSEN_KERNEL_SCRIPT=show_chosen_kernel.py
SHOW_CONFIG_VER_SCRIPT=show_config_version.py
UPDATE_CONFIG_SCRIPT=update_kernel_config.py
CHECK_REQD_PKGS_SCRIPT=required_pkgs.sh
METAPACKAGE_BUILD_SCRIPT=metapackage_build.sh
LOCAL_UPLOAD_SCRIPT=local_upload.sh
WRITE_CHANGELOG_SCRIPT=write_change_log.sh

# Kernel image build target
KERNEL_IMAGE_NAME=bzImage
readonly KERNEL_IMAGE_NAME

# Make oldconfig command
MAKE_CONFIG_COMMAND="make oldconfig"
readonly MAKE_CONFIG_COMMAND

# git clone command
if [ -z "$GIT_CLONE_COMMAND" ]; then
    GIT_CLONE_COMMAND="git clone --depth 1"
    readonly GIT_CLONE_COMMAND
fi


# Name of directory we create
KB_TOP_DIR=__kernel_build
# Dir under DEB_DIR where source package is built
KB_SRC_PKG_DIR=__src_pkg

# Cannot make these variables readonly or export them here, because we
# modify them in set_vars()
#

#-------------------------------------------------------------------------
# Variables for metapackage_build.sh
#-------------------------------------------------------------------------
# Set this to 'yes' to disable passphrase caching by gpg
DISABLE_GPG_PASSPHRASE_CACHING=${DISABLE_GPG_PASSPHRASE_CACHING:-no}
METAPKG_LICENSE=gpl2 # for dh_make
METAPKG_INPUT_FILE_DIR=$(readlink -f ${SCRIPT_DIR}/../config/metapkg_controlfile_templates)
METAPKG_I_DEB=i_deb
METAPKG_I_SRC=i_src
METAPKG_H_DEB=h_deb
METAPKG_H_SRC=h_src
# Tokens replaced in METAPKG_I_DEB, ISRC, METAPKG_H_DEB, METAPKG_H_SRC
METAPKG_TOKEN_VERSION="__VERSION__"
METAPKG_TOKEN_PREFIX="__PKG_PREFIX__"
METAPKG_TOKEN_MAINTAINER="__MAINTAINER__"
METAPKG_CHECK_REQD_PKGS_SCRIPT=${SCRIPT_DIR}/metapackage_required_pkgs.sh

#-------------------------------------------------------------------------
# Variables for local_upload.sh
#-------------------------------------------------------------------------

LOCAL_UPLOAD_CHECK_REQD_PKGS_SCRIPT=${SCRIPT_DIR}/local_upload_required_pkgs.sh

#-------------------------------------------------------------------------
# variables for ppa_upload.sh
#-------------------------------------------------------------------------
PPA_UPLOAD_CHECK_REQD_PKGS_SCRIPT=${SCRIPT_DIR}/upload_required_pkgs.sh


#-------------------------------------------------------------------------
# Probably don't have to change anything below this
#-------------------------------------------------------------------------


#-------------------------------------------------------------------------
# functions
#-------------------------------------------------------------------------
function show_help {
    # If pandoc is available, use it to convert README.md to text
    which pandoc 1>/dev/null 2>&1
    if [ $? -eq 0 ]; then
        pandoc -r markdown_github -w plain "${SCRIPT_DIR}/../README.md"
    fi
    # No pandoc
    if [ -f "${SCRIPT_DIR}/../README" ]; then
        cat "${SCRIPT_DIR}/../README"
    else
        cat "${SCRIPT_DIR}/../README.md"
    fi
}

function check_avail_disk_space() {
    # $1: required space in bytes
    # $2: directory - defaults to .
    # Returns: 0 if enough space available, 1 otherwise
    local REQD_SPACE_BYTES=$1
    local check_dir=${2:-.}

    local AVAIL_SPACE_BYTES=$(df -B1 --output=avail "${check_dir}" | sed -e '1d')
    printf "Required space : %18d\n" $REQD_SPACE_BYTES
    printf "Available space: %18d\n" $AVAIL_SPACE_BYTES
    if [ $AVAIL_SPACE_BYTES -lt $REQD_SPACE_BYTES ]; then
        echo "You do not have enough disk space"
        return 1
    fi
    echo ""
}

function is_git_url() {
    # $1: URL
    # Returns:
    #   0: if URL is a git repository (having a HEAD)
    #   1: otherwise
    GIT_ASKPASS=true git ls-remote "$1" HEAD 1>/dev/null 2>&1
    return $?
}

function is_valid_url() {
    # $1: URL
    # Returns:
    #   0: if URL is a valid HTTP(S) URL
    #   1: otherwise
    curl -s -f -I "$1" 1>/dev/null 2>&1
    return $?
}

function get_hms {
    # Converts a variable like SECONDS to hh:mm:ss format and echoes it
    # $1: value to convert - if not set defaults to using $SECONDS
    if [ -n "$1" ]; then
        duration=$1
    else
        duration=$SECONDS
    fi
    printf "%02d:%02d:%02d" "$(($duration / 3600))" "$(($duration / 60))" "$(($duration % 60))"
}

function show_timing_msg {
    # $1: START_END_TIME_FILEPATH
    # $2: Message
    # $3: tee or not: 'yestee' implies tee
    # $4 (optional): elapsed time (string)
    #
    # Uses: START_END_TIME_FILEPATH if set and accesible, else uses /dev/null
    local outfile=$1
    local mesg=$2
    local teeout=$3
    local elapsed=$4

    touch "$outfile" 1>/dev/null 2>&1 || outfile=/dev/null

    if [ "$teeout" = "yestee" ]; then
        if [ -n "$elapsed" ]; then
            printf "%-39s: %-28s (%s)\n" "$mesg" "$(date)" "$elapsed" | tee -a "$outfile"
        else
            printf "%-39s: %-28s\n" "$mesg" "$(date)" | tee -a "$outfile"
        fi
    else
        if [ -n "$elapsed" ]; then
            printf "%-39s: %-28s (%s)\n" "$mesg" "$(date)" "$elapsed" >> "$outfile"
        else
            printf "%-39s: %-28s\n" "$mesg" "$(date)" >> "$outfile"
        fi
    fi
}

function get_tar_fmt_ind {
	# $1: KERNEL_SRC URL - can be tar / xz / bz2 / gz
	# Echoes single-char fmt indicator - 'j', 'z' or ''
	# Exits (from script) if tar file ($1) has invalid suffix

	local URL=${1}
	local SUFFIX=$(echo "${URL}" | awk -F. '{print $NF}')
	case ${SUFFIX} in
		"tar")
			echo ''
			;;
		"xz")
			echo 'J'
			;;
		"bz2")
			echo 'j'
			;;
		"gz")
			echo 'z'
			;;
		*)
			echo "KERNEL_SRC has unknown suffix ${SUFFIX}: ${URL}"
			return 1
			;;
	esac
}

function choose_num_threads() {
    # Echoes number of threads to use (int)
    # $1: (optional): value of NUM_THREADS environment variable
    local num_threads_env_var=$1

    # Fix NUM_THREADS to be min(NUM_THREADS, number_of_cores)
    local NUM_CORES=$(lscpu | grep '^CPU(s)' | awk '{print $2}')
    local TARGETED_CORES=$(($NUM_CORES - 1))
    if [ $TARGETED_CORES -lt 1 ]; then
        TARGETED_CORES=1
    fi

    if [ -n "$num_threads_env_var" ]; then
        echo $num_threads_env_var | grep -q '^[1-9][0-9]*$'
        if [ $? -eq 0 ]; then
            if [ $num_threads_env_var -gt $TARGETED_CORES ]; then
                >&2 echo "Ignoring NUM_THREADS > (available cores - 1) ($TARGETED_CORES)"
                unset num_threads_env_var
            fi
        else
            >&2 echo "Ignoring invalid value for NUM_THREADS : $num_threads_env_var"
            unset num_threads_env_var
        fi
    fi
    if [ -n "$num_threads_env_var" ]; then
        TARGETED_CORES=$num_threads_env_var
    fi
    echo $TARGETED_CORES
}

function set_vars {
    #-------------------------------------------------------------------------
    # Strip off directory path components if we expect only filenames
    #-------------------------------------------------------------------------
    CONFIG_FILE=$(basename "$CONFIG_FILE")
    CONFIG_PREFS_FILE=$(basename "$CONFIG_PREFS_FILE")
    PATCH_DIR=$(basename "$PATCH_DIR")

    KERNEL_SOURCE_SCRIPT=$(basename "$KERNEL_SOURCE_SCRIPT")
    SHOW_AVAIL_KERNELS_SCRIPT=$(basename "$SHOW_AVAIL_KERNELS_SCRIPT")
    SHOW_CHOSEN_KERNEL_SCRIPT=$(basename "$SHOW_CHOSEN_KERNEL_SCRIPT")
    SHOW_CONFIG_VER_SCRIPT=$(basename "$SHOW_CONFIG_VER_SCRIPT")
    UPDATE_CONFIG_SCRIPT=$(basename "$UPDATE_CONFIG_SCRIPT")
    CHECK_REQD_PKGS_SCRIPT=$(basename "$CHECK_REQD_PKGS_SCRIPT")
    METAPACKAGE_BUILD_SCRIPT=$(basename "$METAPACKAGE_BUILD_SCRIPT")
    LOCAL_UPLOAD_SCRIPT=$(basename "$LOCAL_UPLOAD_SCRIPT")

    COMPILE_OUT_FILENAME=$(basename "$COMPILE_OUT_FILENAME")
    OLDCONFIG_OUT_FILENAME=$(basename "$OLDCONFIG_OUT_FILENAME")
    CHOSEN_OUT_FILENAME=$(basename "$CHOSEN_OUT_FILENAME")
    START_END_TIME_FILE=$(basename "$START_END_TIME_FILE")
    METAPKG_BUILD_OUT=$(basename "$METAPKG_BUILD_OUT")
    LOCAL_UPLOAD_BUILD_OUT=$(basename "$LOCAL_UPLOAD_BUILD_OUT")

    CONFIG_FILE_PATH=$(readlink -f "${SCRIPT_DIR}/../config/${CONFIG_FILE}")
    CONFIG_FILE_PREFS_PATH=$(readlink -f "${SCRIPT_DIR}/../config/${CONFIG_PREFS_FILE}")

    # Required scripts can ONLY be in the same dir as this script
    KERNEL_SOURCE_SCRIPT="${SCRIPT_DIR}/${KERNEL_SOURCE_SCRIPT}"
    SHOW_AVAIL_KERNELS_SCRIPT="${SCRIPT_DIR}/${SHOW_AVAIL_KERNELS_SCRIPT}"
    SHOW_CHOSEN_KERNEL_SCRIPT="${SCRIPT_DIR}/${SHOW_CHOSEN_KERNEL_SCRIPT}"
    SHOW_CONFIG_VER_SCRIPT="${SCRIPT_DIR}/${SHOW_CONFIG_VER_SCRIPT}"
    UPDATE_CONFIG_SCRIPT="${SCRIPT_DIR}/${UPDATE_CONFIG_SCRIPT}"
    CHECK_REQD_PKGS_SCRIPT="${SCRIPT_DIR}/${CHECK_REQD_PKGS_SCRIPT}"
    METAPACKAGE_BUILD_SCRIPT="${SCRIPT_DIR}/${METAPACKAGE_BUILD_SCRIPT}"
    LOCAL_UPLOAD_SCRIPT="${SCRIPT_DIR}/${LOCAL_UPLOAD_SCRIPT}"
    WRITE_CHANGELOG_SCRIPT="${SCRIPT_DIR}/${WRITE_CHANGELOG_SCRIPT}"

    # Fix NUM_THREADS to be min(NUM_THREADS, number_of_cores)
    THREADS_USED=$(choose_num_threads "$NUM_THREADS")
    MAKE_THREADED="make -j${THREADS_USED}"
    INDENT="    "

    # Set variables that CANNOT be overridden as read-only
     for v in COMPILE_OUT_FILENAME OLDCONFIG_OUT_FILENAME \
         CHOSEN_OUT_FILENAME START_END_TIME_FILE KERNEL_SOURCE_SCRIPT \
         SHOW_AVAIL_KERNELS_SCRIPT SHOW_CHOSEN_KERNEL_SCRIPT \
         SHOW_CONFIG_VER_SCRIPT UPDATE_CONFIG_SCRIPT CHECK_REQD_PKGS_SCRIPT \
         METAPACKAGE_BUILD_SCRIPT LOCAL_UPLOAD_SCRIPT THREADS_USED \
         MAKE_THREADED INDENT WRITE_CHANGELOG_SCRIPT
          do
              readonly $v
          done

    # read_config will not override environment vars from config
    read_config || return 1

    # Paths - only setting variables - not creating / deleting directories
    oldpwd=$(pwd)
    if [ -z "$KERNEL_BUILD_DIR" ]; then
        KERNEL_BUILD_DIR=$oldpwd
    fi
    KB_TOP_DIR=${KERNEL_BUILD_DIR}/$(basename ${KB_TOP_DIR})
    KB_TOP_DIR=$(readlink -m "${KB_TOP_DIR}")
    BUILD_DIR_PARENT=${KB_TOP_DIR}/build
    BUILD_DIR=${BUILD_DIR_PARENT}/linux
    DEB_DIR=${KB_TOP_DIR}/debs
    DEBUG_DIR=${KB_TOP_DIR}/debug
    METAPKG_BUILD_DIR=${KB_TOP_DIR}/meta

    # Dir names cannot be changed
     for v in KERNEL_BUILD_DIR KB_TOP_DIR BUILD_DIR_PARENT BUILD_DIR DEB_DIR \
         DEBUG_DIR METAPKG_BUILD_DIR
          do
              readonly $v
          done

    # Debug outputs are always in DEBUG_DIR
    OLDCONFIG_OUT_FILEPATH="${DEBUG_DIR}/${OLDCONFIG_OUT_FILENAME}"
    CHOSEN_OUT_FILEPATH="${DEBUG_DIR}/${CHOSEN_OUT_FILENAME}"
    COMPILE_OUT_FILEPATH="${DEBUG_DIR}/${COMPILE_OUT_FILENAME}"
    START_END_TIME_FILEPATH="${DEBUG_DIR}/$START_END_TIME_FILE"
    METAPKG_BUILD_OUT_FILEPATH="${DEBUG_DIR}/${METAPKG_BUILD_OUT}"
    LOCAL_UPLOAD_BUILD_OUT_FILEPATH="${DEBUG_DIR}/${LOCAL_UPLOAD_BUILD_OUT}"

    # debug filenames cannot be changed
     for v in COMPILE_OUT_FILEPATH OLDCONFIG_OUT_FILEPATH CHOSEN_OUT_FILEPATH \
         START_END_TIME_FILEPATH METAPKG_BUILD_OUT_FILEPATH \
         LOCAL_UPLOAD_BUILD_OUT_FILEPATH
          do
              readonly $v; export $v
          done

    # Config defaults to ~/.kernel_build.config, but can be set using
    # environment variable KERNEL_BUILD_CONFIG
    # Variables that can be overridden by environment variables or in config:
    #
    # KERNEL_CONFIG - config to use for kernel (before applying config prefs)
    # KERNEL_PATCH_DIR - dir with kernel patches
    # KERNEL_CONFIG_PREFS - prefs for values to set in kernel config

    if [ -n "$KERNEL_CONFIG" ]; then
        KERNEL_CONFIG=$(readlink -f "${KERNEL_CONFIG}")
        if [ -f "$KERNEL_CONFIG" ] ; then
            CONFIG_FILE_PATH="${KERNEL_CONFIG}"
        else
            echo "Non-existent config : ${KERNEL_CONFIG}"
            return 1
        fi
    fi
    PATCH_DIR_PATH=$(readlink -f "${SCRIPT_DIR}/../${PATCH_DIR}")
    if [ -n "${KERNEL_PATCH_DIR}" ]; then
        KERNEL_PATCH_DIR=$(readlink -f "${KERNEL_PATCH_DIR}")
        if [ -d "${KERNEL_PATCH_DIR}" ] ; then
            PATCH_DIR_PATH="${KERNEL_PATCH_DIR}"
        else
            echo "Ignoring non-existent patch directory : ${KERNEL_PATCH_DIR}"
            unset PATCH_DIR_PATH
        fi
    fi
    if [ -n "${KERNEL_CONFIG_PREFS}" ]; then
        KERNEL_CONFIG_PREFS=$(readlink -f "${KERNEL_CONFIG_PREFS}")
        if [ ! -f "${KERNEL_CONFIG_PREFS}" ] ; then
            echo "Ignoring non-existent config prefs : ${KERNEL_CONFIG_PREFS}"
            unset KERNEL_CONFIG_PREFS
        fi
    else
        KERNEL_CONFIG_PREFS=$(readlink -f "${SCRIPT_DIR}/../config/config.prefs")
    fi
    readonly CONFIG_FILE_PATH
    if [ -n "$PATCH_DIR_PATH" ]; then readonly PATCH_DIR_PATH; fi
    if [ -n "$KERNEL_CONFIG_PREFS" ]; then readonly KERNEL_CONFIG_PREFS; fi


    # Kernel build target - defaults to deb-pkg - source + binary
    # but can set KERNEL__BUILD_SRC_PKG environment variable to choose
    # to build binary only. If only binary deb is built, it cannot
    # be uploaded to Launchpad PPA, but can be uploaded to bintray

    KERNEL_BUILD_TARGET=deb-pkg
    if [ "$KERNEL__BUILD_SRC_PKG" = "no" ]; then
        echo "Not building source packages: KERNEL__BUILD_SRC_PKG = $KERNEL__BUILD_SRC_PKG"
        KERNEL_BUILD_TARGET=bindeb-pkg
    fi
    readonly KERNEL_BUILD_TARGET

    # We can set KERN_VER early using SHOW_CHOSEN_KERNEL_SCRIPT
    # so that we can run metapackage_build.sh as soon as possible
    if [ -z "$KERNEL_SOURCE_URL" ]; then
        KERN_VER=$(${SHOW_CHOSEN_KERNEL_SCRIPT})

        if [ $? -eq 0 ]; then
            if [[ $KERN_VER == unknown* ]] ; then
                unset KERN_VER
            else
                readonly KERN_VER
            fi
        else
            unset KERN_VER
        fi
    fi
}

function create_dirs {
    BAD_DIR_MSG="Linux kernel cannot be built under a path containing spaces or colons
This is a limitation of the Linux kernel Makefile - you will get an error
that looks like:
  Makefile:128: *** main directory cannot contain spaces nor colons.  Stop."

    if [ -z "${KERNEL_BUILD_DIR}" ]; then
        echo "KERNEL_BUILD_DIR not set - this is a bug"
        return 1
    else
        case "${KERNEL_BUILD_DIR}" in
                *\ * )
                    echo "$BAD_DIR_MSG"
                    return 1
                    ;;
                *:* )
                    echo "$BAD_DIR_MSG"
                    return 1
                    ;;
        esac
        if [ ! -d "$KERNEL_BUILD_DIR" ]; then
            mkdir -p "$KERNEL_BUILD_DIR"
            if [ $? -ne 0 ]; then
                echo "KERNEL_BUILD_DIR does not exist and cannot be created: $KERNEL_BUILD_DIR"
                return 1
            fi
        fi
    fi
    # Dir deletion
    \rm -rf $KB_TOP_DIR
    if [ $? -ne 0 ]; then
        echo "Could not delete KERNEL_BUILD_DIR : $KERNEL_BUILD_DIR"
        return 1
    fi
    # Not BUILD_DIR - will create from kernel source
    for v in KERNEL_BUILD_DIR KB_TOP_DIR BUILD_DIR_PARENT DEB_DIR \
        DEBUG_DIR METAPKG_BUILD_DIR
        do
            if [ ! -d "${!v}" ]; then
                mkdir -p "${!v}"
                if [ $? -ne 0 ]; then
                    echo "$v does not exist and cannot be created: ${!v}"
                    return 1
                fi
            fi
        done

    # Create the debug files
    for v in OLDCONFIG_OUT_FILEPATH CHOSEN_OUT_FILEPATH COMPILE_OUT_FILEPATH \
        START_END_TIME_FILEPATH METAPKG_BUILD_OUT_FILEPATH \
        LOCAL_UPLOAD_BUILD_OUT_FILEPATH
        do
            touch "${!v}"
            if [ $? -ne 0 ]; then
                echo "Could not create / write $v : ${!v}"
                return 1
            fi
        done
}

function show_vars() {
    # Print what we are using

    # echo "Read-only variables:"
    # readonly -p | cut -d' ' -f3- | cut -d'=' -f1 | sed -e "s/^/    /" | egrep -v '(BASH*|EUID|PPID|SHELLOPTS|UID|UPDATE_CONFIG_SCRIPT)'

    printf "%-24s : %s\n" "KERNEL_TYPE" "${KERNEL_TYPE:-not set}"
    printf "%-24s : %s\n" "KERNEL_VERSION" "${KERNEL_VERSION:-not set}"
    printf "%-24s : %s\n" "KERNEL_BUILD_DIR" "${KERNEL_BUILD_DIR:-not set}"
    printf "%-24s : %s\n" "BUILD_DIR_PARENT" "${BUILD_DIR_PARENT:-not set}"
    printf "%-24s : %s\n" "BUILD_DIR" "${BUILD_DIR:-not set}"
    printf "%-24s : %s\n" "DEB_DIR" "${DEB_DIR:-not set}"
    printf "%-24s : %s\n" "DEBUG_DIR" "${DEBUG_DIR:-not set}"
    printf "%-24s : %s\n" "METAPKG_BUILD_DIR" "${METAPKG_BUILD_DIR:-not set}"
    printf "%-24s : %s\n" "Patch dir" "${PATCH_DIR_PATH:-not set}"

    printf "%-24s : %s\n" "Config file" "${CONFIG_FILE_PATH:-not set}"
    printf "%-24s : %s\n" "Config prefs" "${KERNEL_CONFIG_PREFS:-not set}"
    printf "%-24s : %s\n" "Threads" "${THREADS_USED:-not set}"
    printf "%-24s : %s\n" "Build target" "${KERNEL_BUILD_TARGET:-not set}"

    printf "%-24s : %s\n" "Config choices output" "$CHOSEN_OUT_FILEPATH"
    printf "%-24s : %s\n" "make oldconfig output" "$OLDCONFIG_OUT_FILEPATH"
    printf "%-24s : %s\n" "Compile output" "$COMPILE_OUT_FILEPATH"

    printf "%-24s : %s\n" "Metapackage build output" "$METAPKG_BUILD_OUT_FILEPATH"
    printf "%-24s : %s\n" "Local upload output" "$LOCAL_UPLOAD_BUILD_OUT_FILEPATH"

    printf "%-24s : %s\n" "Applying patches" "${KERNEL__APPLY_PATCHES:-yes}"
    printf "%-24s : %s\n" "Building source packages" "${KERNEL__BUILD_SRC_PKG:-yes}"
    printf "%-24s : %s\n" "Build metapackages" "${KERNEL__BUILD_META_PACKAGE:-yes}"
    printf "%-24s : %s\n" "Local repository upload" "${KERNEL__DO_LOCAL_UPLOAD:-yes}"
}

function read_config {
    #-------------------------------------------------------------------------
    # Uses KERNEL_BUILD_CONFIG if set to choose config file - defaults to
    # ~/.kernel_build.config
    # If KERNEL_BUILD_CONFIG is not set, ~/.kernel_build.config is used
    # If KERNEL_BUILD_CONFIG is set to "/dev/null", NO config is used
    # If config file is found - through KERNEL_BUILD_CONFIG or the default
    #     AND sourcing config gives an error
    # THEN it is an ERROR
    # If config file is found - through KERNEL_BUILD_CONFIG or the default
    #     AND config is missing or cannot be read, config is IGNORED - same
    #     as setting KERNEL_BUILD_CONFIG=/dev/null
    #-------------------------------------------------------------------------

    if [ "$KERNEL_BUILD_CONFIG" = "/dev/null" ]; then
        echo "Not using any config: KERNEL_BUILD_CONFIG = /dev/null"
        return
    fi
    if [ -n "$KERNEL_BUILD_CONFIG" ]; then
        KBUILD_CONFIG=$KERNEL_BUILD_CONFIG
    fi
    if [ -f "$KBUILD_CONFIG" ]; then
        if [ -r "$KBUILD_CONFIG" ]; then
            . "$KBUILD_CONFIG" 2>/dev/null
            if [ $? -ne 0 ]; then
                echo "Error sourcing KERNEL_BUILD_CONFIG : $KBUILD_CONFIG"
                return 1
            fi
        else
            echo "Ignoring unreadable KERNEL_BUILD_CONFIG : $KBUILD_CONFIG"
        fi
    else
        echo "Ignoring missing KERNEL_BUILD_CONFIG : $KBUILD_CONFIG"
    fi
    
    #-------------------------------------------------------------------------
    # Export all config / environment variables that are set (for sub-shells)
    #-------------------------------------------------------------------------
    for v in $CONFIG_VARS
    do
        if [ -n "${!v}" ]; then export $v; fi
    done
}

function is_linux_kernel_source()
{
    # $1: kernel directory containing Makefile
    # Returns: 0 if it looks like linux kernel Makefile
    #          1 otherwise
    # Outputs to COMPILE_OUT_FILEPATH if set and accessible, else to stdout

    local outfile=$COMPILE_OUT_FILEPATH
    touch "$COMPILE_OUT_FILEPATH" 1>/dev/null 2>&1 || outfile=/dev/stdout

    local help_out=$(make -s -C "$1" help)
    if [ $? -ne 0 ]; then
        return 1
    fi
    # As of 4.16 silentoldconfig has moved to PHONY in scripts/kconfig/Makefile!
    # so make help no longer lists silentoldconfig. Now also check for 'generic'
    # linux kernel targets and packaging targets
    # for target in clean mrproper distclean config menuconfig xconfig oldconfig defconfig modules_install modules_prepare kernelversion kernelrelease install
    ret=0
    for target in clean mrproper distclean config menuconfig xconfig oldconfig defconfig modules_install modules_prepare kernelversion kernelrelease install rpm-pkg binrpm-pkg deb-pkg bindeb-pkg 

    do
        echo "$help_out" | grep -q "^[[:space:]][[:space:]]*$target[[:space:]][[:space:]]*-[[:space:]]"
        if [ $? -ne 0 ]; then
            echo "Target not found: $target" 1>>"${outfile}"
            ret=1
        fi
    done
    # As of 4.17.0, silentoldconfig now renamed to syncconfig and is an 
    # implementation detail - we should only use oldconfig!
    return $ret
}

function kernel_version()
{
    # $1: kernel directory containing Makefile
    #     May be:
    #         - Kernel build directory
    #         - /lib/modules/<kern_ver>/build
    #
    # If it is not a linux kernel source dir, will echo kernel version and return 0
    # If it is not a linux kernel source dir containing a Makefile
    # supporting kernelversion target, will echo nothing and return 1
    #
    if [ -z "$1" ]; then
        return 1
    fi
    local KERN_DIR=$(readlink -f "$1")
    if [ ! -d "$KERN_DIR" ]; then
        return 1
    fi
    is_linux_kernel_source "$KERN_DIR" || return 1
    # (At least newer) kernel Makefiles have a built in target to return kernel version
    echo $(make -s -C "$KERN_DIR" -s kernelversion 2>/dev/null)
    return $?
}

function get_kernel_source_tar() {
    # $1: URL
    # Will extract under BUILD_DIR_PARENT and rename top-level dir to BUILD_DIR
    local kurl="$1"
    is_valid_url "$1"
    if [ $? -ne 0 ]; then
        echo "Invalid kernel source URL: $kurl"
        return 1
    fi

    oldpwd=$(pwd)
    cd $BUILD_DIR_PARENT || return 1

    local TAR_FMT_IND=$(get_tar_fmt_ind "$kurl")
    if [ $? -ne 0 ]; then
        echo "URL suffix not supported"
        return 1
    fi
    show_timing_msg "${START_END_TIME_FILEPATH}" "Retrieve kernel source start" "yestee"
    SECONDS=0
    wget -q -O - -nd "$kurl" | tar "${TAR_FMT_IND}xf" -
    show_timing_msg "${START_END_TIME_FILEPATH}" "Retrieve kernel source finished" "yestee" "$(get_hms)"
    local num_dirs=$(echo $(find . -maxdepth 1 -type d -ls) | wc -l)
    if [ $num_dirs -gt 1 ]; then
        echo "Kernel source created more than one dir"
        return 1
    fi
    local kernel_dir=$(find . -maxdepth 1 -type d | sed -e 's/^\.//' -e 's/^\///')
    \mv -f $kernel_dir $BUILD_DIR
    if [ $? -ne 0 ]; then
        echo "Could not rename $kernel_dir to $BUILD_DIR"
        return 1
    fi
    cd $oldpwd
}

function get_kernel_source_git() {
    # $1: URL
    # Will extract under BUILD_DIR_PARENT to BUILD_DIR
    # Assumes that $1 has already been verified to be a git URL
    oldpwd=$(pwd)
    cd $BUILD_DIR_PARENT || return 1
    show_timing_msg "${START_END_TIME_FILEPATH}" "Retrieve kernel source start" "yestee"
    SECONDS=0
    $GIT_CLONE_COMMAND "$1" linux || return 1
    show_timing_msg "${START_END_TIME_FILEPATH}" "Retrieve kernel source finished" "yestee" "$(get_hms)"
    cd $oldpwd
}

function can_build_metapackage_first() {
    # If KERNEL_TYPE is linux-next or torvalds or a custom URL, we cannot know
    # the kernel version until the source is downloaded
    # Returns 0 if build_metapackages can be called before get_kernel_source
    # 1 otherwise

    if [ -z "$KERN_VER" ]; then
        return 1
    fi
    if [[ $KERN_VER == unknown* ]] ; then
        return 1
    fi
    if [ -n "$KERNEL_SOURCE_URL" ]; then
        return 1
    fi
    return 0

}

function get_kernel_source {
    # Also calls build_metapackages - before or after retrieving kernel source
    # Depending on whether kernel version is known before retrieving kernel
    # source

    # Uses:
    #   START_END_TIME_FILEPATH
    #   KERNEL_SOURCE_SCRIPT
    #   BUILD_PARENT_DIR
    #   BUILD_DIR

    local kurl=""
    if [ -n "$KERNEL_SOURCE_URL" ]; then
        kurl=$KERNEL_SOURCE_URL
        if [ -x "$SHOW_CONFIG_VER_SCRIPT" ]; then
            $SHOW_CONFIG_VER_SCRIPT
        fi
    else
        if [ ! -x "${KERNEL_SOURCE_SCRIPT}" ]; then
            echo "Kernel source script not found: ${KERNEL_SOURCE_SCRIPT}"
            return 1
        fi
        local kurl=$(${KERNEL_SOURCE_SCRIPT})
        if [ -z "${kurl}" ]; then
            echo "Could not get kernel source URL from ${KERNEL_SOURCE_SCRIPT}"
            return 1
        fi
        # Show available kernels and kernel version of available config
        if [ -x "${SHOW_AVAIL_KERNELS_SCRIPT}" ]; then
            $SHOW_AVAIL_KERNELS_SCRIPT
        fi
    fi

    # First check if it is a git repo
    if [[ $kurl == git://* ]] || [[ $kurl == *.git ]] ; then
        is_git_url "$kurl"
        if [ $? -eq 0 ]; then
            get_kernel_source_git "$kurl"
            return $?
        else
            echo "Not a git URL: $kurl"
            return 1
        fi
    # Is it ending in a tar suffix that we know?
    elif [[ $kurl == *.tar ]] || [[ $kurl == *.tar.gz ]] || [[ $kurl == *.tar.bz2 ]] || [[ $kurl == *.tar.xz ]] ; then
        is_valid_url "$kurl"
        if [ $? -eq 0 ]; then
            get_kernel_source_tar "$kurl"
            return $?
        else
            echo "Not a git URL: $kurl"
            return 1
        fi
    else
        # Didn't match known patterns - cannot handle it as a TAR URL
        # since we already checked the endings we support
        is_git_url "$kurl"
        if [ $? -eq 0 ]; then
            get_kernel_source_git "$kurl"
            return $?
        else
            echo "Cannot process kernel source URL: $kurl"
            return 1
        fi
    fi
}

function apply_patches {
    #
    # Uses:
    #   PATCH_DIR_PATH
    #   BUILD_DIR
    #
    if [ "$KERNEL__APPLY_PATCHES"  = "no" ]; then
        echo "Not applying any patches: KERNEL__APPLY_PATCHES = $KERNEL__APPLY_PATCHES"
        return
    fi

    if [ -z "$PATCH_DIR_PATH" ]; then
        echo "Patch directory not set. Not applying any patches"
        return
    fi
    if [ ! -d "$PATCH_DIR_PATH" ]; then
        echo "Not a directory: PATCH_DIR_PATH: $PATCH_DIR_PATH"
        echo "Not applying any patches"
        return
    fi
    local num_patches=$(ls -1 "$PATCH_DIR_PATH"/ | wc -l)
    if [ $num_patches -eq 0 ]; then
        echo "No patches to apply"
        return
    fi
    echo "Number of patches to apply: $num_patches"
    if [ ! -d "$BUILD_DIR" ]; then
        echo "Not a directory: BUILD_DIR: $BUILD_DIR"
        echo "Not applying any patches"
        return
    fi
    local oldpwd=$(pwd)
    cd "${BUILD_DIR}"

    ls -1 "$PATCH_DIR_PATH"/* | while read patch_file
    do
        local base_patch_file=$(basename "$patch_file")
        local opt_stripped=$(basename "$patch_file" .optional)
        local mandatory=1
        if [ "$base_patch_file" = "${opt_stripped}.optional" ]; then
            mandatory=0
        fi
        if [ $mandatory -eq 0 ]; then
            echo "Applying optional patch: $base_patch_file:"
        else
            echo "Applying mandatory patch: $base_patch_file:"
        fi
        local patch_out=$(patch --forward -r - -p1 < $patch_file 2>&1)
        patch_ret=$?
        echo "$patch_out" | sed -e "s/^/${INDENT}/"
        if [ $mandatory -eq 1 -a $patch_ret -ne 0 ]; then
            echo "Mandatory patch failed"
            cd $oldpwd
            return 1
        fi
    done
    cd $oldpwd
}

function restore_kernel_config {
    #
    # Uses:
    #   BUILD_DIR
    #   CONFIG_FILE_PATH
    #

    local oldpwd=$(pwd)
    cd "$BUILD_DIR"
    if [ ! -f .config ]; then
        if [ -f "${CONFIG_FILE_PATH}" ]; then
            cp "${CONFIG_FILE_PATH}" .config
            local config_kern_ver_lines="$(grep '^# Linux.* Kernel Configuration' ${CONFIG_FILE_PATH})"
            if [ $? -eq 0 ]; then
                local kver=$(echo "$config_kern_ver_lines" | head -1 | awk '{print $3}')
                echo "Restored config: seems to be from version $kver"
            else
                echo "Restored config (version not found in comment)"
            fi
        else
            echo ".config not found: ${CONFIG_FILE_PATH}"
            cd $oldpwd
            return 1
        fi
    fi
    cd $oldpwd
}

function run_make_oldconfig {
    #
    # Uses:
    #   BUILD_DIR
    #   UPDATE_CONFIG_SCRIPT
    #   OLDCONFIG_OUT_FILEPATH
    #   CHOSEN_OUT_FILEPATH
    #   KERNEL_CONFIG_PREFS
    #

    # Runs make silentoldconfig, answering any questions
    # Expects the following:
    #   - Linux source should have been retrieved and extracted
    #   - BUILD_DIR should have been set (set_build_dir)
    #   - .config must have already been restored (restore_kernel_config)
    #   - $UPDATE_CONFIG_SCRIPT must have been set and must be executable
    # If any of the above expectations are NOT met, compilation aborts

    # If $CONFIG_PREFS is set and read-able:
    #   If $UPDATE_CONFIG_SCRIPT is set and executable, it is run
    # If (and only if) $UPDATE_CONFIG_SCRIPT return code is 100,
    # make silentoldconfig is called for SECOND time, again using 
    # $UPDATE_CONFIG_SCRIPT
    if [ -z "$BUILD_DIR" ]; then
        echo "BUILD_DIR not set"
        return 1
    fi
    if [ ! -d "$BUILD_DIR" ]; then
        echo "BUILD_DIR is not a directory: $BUILD_DIR"
        return 1
    fi
    if [ ! -f "${BUILD_DIR}/.config" ]; then
        echo ".config not found: ${BUILD_DIR}/.config"
        return 1
    fi
    if [ -z "$UPDATE_CONFIG_SCRIPT" ]; then
        echo "UPDATE_CONFIG_SCRIPT not set"
        return 1
    fi
    if [ ! -x "$UPDATE_CONFIG_SCRIPT" ]; then
        echo "Not executable: $UPDATE_CONFIG_SCRIPT"
        return 1
    fi
    
    local oldpwd="$(pwd)"
    cd "${BUILD_DIR}"
    PYTHONUNBUFFERED=yes $UPDATE_CONFIG_SCRIPT "${BUILD_DIR}" "${OLDCONFIG_OUT_FILEPATH}" "${CHOSEN_OUT_FILEPATH}" "${MAKE_CONFIG_COMMAND}" "${KERNEL_CONFIG_PREFS}"
    ret=$?

    cd "$oldpwd"
    return $ret
}

function build_kernel {
    #
    # Uses:
    #   COMPILE_OUT_FILEPATH
    #   MAKE_THREADED
    #   KERNEL_IMAGE_NAME
    #   KERNEL_BUILD_TARGET
    #   START_END_TIME_FILEPATH
    #   DEB_DIR
    #   OLDCONFIG_OUT_FILEPATH
    #

    local oldpwd="$(pwd)"
    cd $BUILD_DIR
    SECONDS=0
    \cp -f /dev/null "${COMPILE_OUT_FILEPATH}"
    local elapsed=''

    show_timing_msg "${START_END_TIME_FILEPATH}" "Kernel build start" "yestee" ""
    run_make_oldconfig
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && cd "$oldpwd" && return 1
    $MAKE_THREADED $KERNEL_IMAGE_NAME 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && cd "$oldpwd" && return 1
    show_timing_msg "${START_END_TIME_FILEPATH}" "Kernel $KERNEL_IMAGE_NAME build finished" "yestee" "$(get_hms)"

    show_timing_msg "${START_END_TIME_FILEPATH}" "Kernel modules build start" "notee" ""; SECONDS=0
    $MAKE_THREADED modules 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && cd "$oldpwd" && return 1
    show_timing_msg "${START_END_TIME_FILEPATH}" "Kernel modules build finished" "yestee" "$(get_hms)"

    # Cannot easily write a more comprehensive changelog before building binary debs
    # debian/changelog is created within scripts/packages/mkdebian which is called
    # when 'make bindeb-pkg' or 'make deb-pkg'
    # The textthat goes into the changelog (and control files) are hard-coded in
    # scripts/packages/mkdebian !

    show_timing_msg "${START_END_TIME_FILEPATH}" "Kernel deb build start" "notee" ""; SECONDS=0
    $MAKE_THREADED ${KERNEL_BUILD_TARGET} 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && cd "$oldpwd" && return 1

    show_timing_msg "${START_END_TIME_FILEPATH}" "Kernel deb build finished" "yestee" "$(get_hms)"
    show_timing_msg "${START_END_TIME_FILEPATH}" "Kernel build finished" "notee" ""

    cd  "${BUILD_DIR_PARENT}"
    find . -maxdepth 1 -type f -exec mv {} ${DEB_DIR}/ \;
    rm -f "${OLDCONFIG_OUT_FILEPATH}"

    echo "-------------------------- Kernel compile time -------------------------------"
    cat $START_END_TIME_FILEPATH
    echo "------------------------------------------------------------------------------"
    echo "Kernel DEBS: (in $(readlink -f $DEB_DIR))"
    cd "${DEB_DIR}"
    ls -1 *.deb | sed -e "s/^/${INDENT}/"
    echo "------------------------------------------------------------------------------"


    cd "$oldpwd"
}

function build_metapackages() {
    #
    # Uses:
    #   KERNEL__BUILD_META_PACKAGE
    #   SCRIPT_DIR
    #   METAPKG_BUILD_DIR
    #   KERNEL_VERSION
    #   KERNEL_BUILD_DIR
    #   SCRIPT_DIR
    #

    if [ "$KERNEL__BUILD_META_PACKAGE" = "no" ]; then
        echo "Not building metapackages: KERNEL__BUILD_META_PACKAGE = $KERNEL__BUILD_META_PACKAGE"
        return
    fi

    if [ -x "${METAPACKAGE_BUILD_SCRIPT}" -a -n "$METAPKG_BUILD_DIR" ]; then
        echo ""
        echo "--------- Building metapackages ----------"
        echo "You will have to enter your passphrase for signing metapackages"
        echo ""
        "${METAPACKAGE_BUILD_SCRIPT}" || exit 1
    else
        if [ -z "$METAPKG_BUILD_DIR" ]; then
            echo "METAPKG_BUILD_DIR not set - Not building metapackages"
        else 
            echo "Metapackage build script not found: ${METAPACKAGE_BUILD_SCRIPT}"
            echo "Not building metapackages"
        fi
    fi
}

function do_local_upload() {
    # Uses:
    #   KERNEL__DO_LOCAL_UPLOAD
    #   LOCAL_UPLOAD_SCRIPT
    #   METAPKG_BUILD_DIR
    #

    if [ "$KERNEL__DO_LOCAL_UPLOAD" = "no" ]; then
        echo "Not calling $(basename $LOCAL_UPLOAD_SCRIPT): KERNEL__DO_LOCAL_UPLOAD = $KERNEL__DO_LOCAL_UPLOAD"
        return
    fi

    if [ -z "$METAPKG_BUILD_DIR" ]; then
        echo "METAPKG_BUILD_DIR not set - Not calling $(basename $LOCAL_UPLOAD_SCRIPT)"
        exit 0
    fi

    if [ -x "${LOCAL_UPLOAD_SCRIPT}" ]; then
        # KERNEL_VERSION=$KERN_VER KERNEL_BUILD_DIR=$DEB_DIR "${LOCAL_UPLOAD_SCRIPT}"
        KERNEL_VERSION=$KERN_VER "${LOCAL_UPLOAD_SCRIPT}"
    fi
}


# ------------------------------------------------------------------------
# functions for metapackage_build.sh
# ------------------------------------------------------------------------
function disable_gpg_passphrase_caching() {
    if [ "$DISABLE_GPG_PASSPHRASE_CACHING" = "yes" ] ;then
        gpgconf --kill gpg-agent
    fi
}

function metapkg_exit_with_msg() {
    # $1: Message
    echo "$1"
    echo "See complete output in $METAPKG_BUILD_OUT_FILEPATH"
    exit 1
}

function metapkg_show_vars() {
    echo "METAPKG_BUILD_DIR:       ${METAPKG_BUILD_DIR:-unset}"
    echo "METAPKG_INPUT_FILE_DIR:  $METAPKG_INPUT_FILE_DIR"
    echo "META_PKGNAME_PREFIX:     ${META_PKGNAME_PREFIX:-unset}"
    echo "DEBEMAIL:                ${DEBEMAIL:-unset}"
    echo "DEBFULLNAME:             ${DEBFULLNAME:-unset}"
    echo "KERN_VER:                ${KERN_VER:-unset}"
    echo "MAINTAINER:              ${MAINTAINER:-unset}"
    echo "DISTRIBUTION:            ${DISTRIBUTION:-unset}"
    echo "Build output in:         ${METAPKG_BUILD_OUT_FILEPATH:-unset}"
}


function metapkg_set_vars() {
    if [ -z "$DEBEMAIL" ]; then
        echo "DEBEMAIL must be set"
        exit 1
    fi
    if [ -z "$KERN_VER" ]; then
        echo "KERN_VER must be set"
        exit 1
    fi
    MAINTAINER="${DEBFULLNAME} <${DEBEMAIL}>"
    DISTRIBUTION=$(lsb_release -c | awk '{print $2}')
}

function metapkg_check_input_files() {
    METAPKG_I_DEB="${METAPKG_INPUT_FILE_DIR}/$METAPKG_I_DEB"
    METAPKG_I_SRC="${METAPKG_INPUT_FILE_DIR}/$METAPKG_I_SRC"
    METAPKG_H_DEB="${METAPKG_INPUT_FILE_DIR}/$METAPKG_H_DEB"
    METAPKG_H_SRC="${METAPKG_INPUT_FILE_DIR}/$METAPKG_H_SRC"

    ERRS=0
    for f in $METAPKG_I_DEB $METAPKG_I_SRC $METAPKG_H_DEB $METAPKG_H_SRC
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

function metapkg_build_debs() {
    # $1: image|headers
    # $2: control file: $METAPKG_I_DEB or $METAPKG_H_DEB

    local PKG_NAME_EXT="$1"
    local PKG_CONTROL_FILE="$2"
    cat "$PKG_CONTROL_FILE" | sed -e "s/${METAPKG_TOKEN_VERSION}/${KERN_VER}/g" -e "s/${METAPKG_TOKEN_PREFIX}/${META_PKGNAME_PREFIX}/g" -e "s/${METAPKG_TOKEN_MAINTAINER}/${MAINTAINER}/g" > "${METAPKG_BUILD_DIR}/${PKG_NAME_EXT}"
    (cd "${METAPKG_BUILD_DIR}"; equivs-build ${PKG_NAME_EXT} 1>>"$METAPKG_BUILD_OUT_FILEPATH" 2>&1 && rm -f "${METAPKG_BUILD_DIR}/${PKG_NAME_EXT}" || metapkg_exit_with_msg "equivs-build ${PKG_NAME_EXT} failed")
    echo "Binary deb built:        $(ls -1 ${METAPKG_BUILD_DIR}/${META_PKGNAME_PREFIX}-${PKG_NAME_EXT}_${KERN_VER}_all.deb 2>/dev/null)"
}

function metapkg_build_src_debs() {
    # $1: image|headers
    # $2: control file: $METAPKG_I_SRC or $METAPKG_H_SRC

    local PKG_NAME_EXT="$1"
    local PKG_CONTROL_FILE="$2"

    local TEMP_DIR="${METAPKG_BUILD_DIR}/${META_PKGNAME_PREFIX}-${PKG_NAME_EXT}-${KERN_VER}"
    \rm -rf "${TEMP_DIR}"
    mkdir -p "${TEMP_DIR}"
    cd "$TEMP_DIR"

    dh_make -i -e"$DEBEMAIL" --createorig -c "$METAPKG_LICENSE" --indep -p ${META_PKGNAME_PREFIX}-${PKG_NAME_EXT} -y -n 1>>"$METAPKG_BUILD_OUT_FILEPATH" 2>&1 || metapkg_exit_with_msg "dh_make ${META_PKGNAME_PREFIX}-${PKG_NAME_EXT} failed"
    \rm -f debian/*.ex debian/*.EX debian/README.Debian debian/README.source
    # Fix distribution that is EMBEDDED in changelog!
    sed --in-place "1 s/ unstable;/ ${DISTRIBUTION};/" debian/changelog
    sed --in-place "s/^Version: *$/Version: ${KERN_VER}/" debian/control

    # Write a more comprehensive changelog
    if [ -x "$WRITE_CHANGELOG_SCRIPT" ]; then
        $WRITE_CHANGELOG_SCRIPT
        if [ -f debian/changelog ]; then
            cat debian/changelog >>"${COMPILE_OUT_FILEPATH}"
        fi
    else
        echo "WRITE_CHANGELOG_SCRIPT not found: $WRITE_CHANGELOG_SCRIPT"
    fi

    cat "$PKG_CONTROL_FILE" | sed -e "s/${METAPKG_TOKEN_VERSION}/${KERN_VER}/g" -e "s/${METAPKG_TOKEN_PREFIX}/${META_PKGNAME_PREFIX}/g" -e "s/${METAPKG_TOKEN_MAINTAINER}/${MAINTAINER}/g" > debian/control

    disable_gpg_passphrase_caching   # depending on DISABLE_GPG_PASSPHRASE_CACHING

    dpkg-buildpackage -S -e"${MAINTAINER}"  -m"${MAINTAINER}" 1>>"$METAPKG_BUILD_OUT_FILEPATH" 2>&1 || metapkg_exit_with_msg "dpkg-buildpackage ${META_PKGNAME_PREFIX}-${PKG_NAME_EXT} failed"

    cd "${SCRIPT_DIR}"
    \rm -rf "${TEMP_DIR}"
    echo "Source deb built:        $(ls -1 ${METAPKG_BUILD_DIR}/${META_PKGNAME_PREFIX}-${PKG_NAME_EXT}_${KERN_VER}_source.changes 2>/dev/null)"
}


#-------------------------------------------------------------------------
# functions for local_upload.sh
#-------------------------------------------------------------------------

function local_upload_set_vars() {
    if [ -z "$LOCAL_DEB_DISTS" ]; then
        LOCAL_DEB_DISTS=$(lsb_release -c | awk '{print $2}')
    fi

    echo "LOCAL_DEB_REPO_DIR:      ${LOCAL_DEB_REPO_DIR:-unset}"
    echo "LOCAL_DEB_DISTS:         ${LOCAL_DEB_DISTS:-unset}"
    echo "Build output in:         ${LOCAL_UPLOAD_BUILD_OUT_FILEPATH:-unset}"
}

function local_upload_do_kernel_upload() {
    cd $DEB_DIR
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
            reprepro --basedir $LOCAL_DEB_REPO_DIR includedeb $dist $deb_file >> ${LOCAL_UPLOAD_BUILD_OUT_FILEPATH} 2>&1
            if [ $? -ne 0 ]; then
                echo "FAILED: Adding $deb_file to dist $dist - see ${LOCAL_UPLOAD_BUILD_OUT_FILEPATH}"
            fi
        done
    done
}

function local_upload_do_metapkg_upload() {
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
            reprepro --basedir $LOCAL_DEB_REPO_DIR includedeb $dist $deb_file >> ${LOCAL_UPLOAD_BUILD_OUT_FILEPATH} 2>&1
            if [ $? -ne 0 ]; then
                echo "FAILED: Adding $deb_file to dist $dist - see ${LOCAL_UPLOAD_BUILD_OUT_FILEPATH}"
            fi
        done
    done
}

#-------------------------------------------------------------------------
# functions for ppa_upload.sh
#-------------------------------------------------------------------------

function ppa_upload_check_deb_dir {
    # Everything in this script depends on DEB_DIR being set, existing
    # and containing exactly one filename ending in .dsc
    # The rest of the checks are done by dpkg-source -x

    if [ -z "$DEB_DIR" ]; then
        echo "DEB_DIR not set, cannot proceed"
        return 1
    fi
    if [ ! -d "$DEB_DIR" ]; then
        echo "DEB_DIR not a directory: $DEB_DIR"
        return 1
    fi
    local num_dsc_files=$(ls $DEB_DIR/linux-*.dsc 2>/dev/null | wc -l)
    if [ $num_dsc_files -lt 1 ]; then
        echo "No DSC file found in $DEB_DIR"
        return 1
    elif [ $num_dsc_files -gt 1 ]; then
        echo "More than one DSC file found in $DEB_DIR"
        ls -1 $DEB_DIR/linux-*.dsc | sed -e 's/^/    /'
        return 1
    fi
    return 0
}

function ppa_upload_set_vars {
    local oldpwd=$(pwd)
    cd "${DEB_DIR}"

    PPA_UPLOAD_DSC_FILE=$(ls -1 linux-*.dsc | head -1)
    PPA_UPLOAD_TAR_FILE=$(ls -1 *.orig.tar.gz | head -1)
    PPA_UPLOAD_DEBIAN_TAR_FILE=$(ls -1 *.debian.tar.gz 2>/dev/null | head -1)
    # Kernel 4.17.6 seems to have started using .diff.gz instead of .debian.tar.gz!
    PPA_UPLOAD_DIFF_GZ_FILE=$(ls -1 linux-*.diff.gz | head -1)
    PPA_UPLOAD_DSC_FILE=$(basename $PPA_UPLOAD_DSC_FILE)
    PPA_UPLOAD_TAR_FILE=$(basename $PPA_UPLOAD_TAR_FILE)
    if [ -n "$PPA_UPLOAD_DEBIAN_TAR_FILE" ]; then
        PPA_UPLOAD_DEBIAN_TAR_FILE=$(basename $PPA_UPLOAD_DEBIAN_TAR_FILE)
    fi
    if [ -n "$PPA_UPLOAD_DIFF_GZ_FILE" ]; then
        PPA_UPLOAD_DIFF_GZ_FILE=$(basename $PPA_UPLOAD_DIFF_GZ_FILE)
    fi

    # Print what we are using
    printf "%-24s : %s\n" "DEBS built in" "${DEB_DIR}"
    printf "%-24s : %s\n" "PPA_UPLOAD_DSC_FILE" "$PPA_UPLOAD_DSC_FILE"
    printf "%-24s : %s\n" "PPA_UPLOAD_TAR_FILE" "$PPA_UPLOAD_TAR_FILE"
    printf "%-24s : %s\n" "PPA_UPLOAD_DEBIAN_TAR_FILE" "$PPA_UPLOAD_DEBIAN_TAR_FILE"
    printf "%-24s : %s\n" "PPA_UPLOAD_DIFF_GZ_FILE" "$PPA_UPLOAD_DIFF_GZ_FILE"
    printf "%-24s : %s\n" "Build output" "$COMPILE_OUT_FILEPATH"

    cd $oldpwd
}

function ppa_upload_build_src_changes {
    # (If we used 'make deb-pkg' and not 'make bindeb-pkg') we look for .dsc file
    # If .dsc file exists, we do the following:
    #   - Build-Depends field is updated - we KNOW what it should be
    #   - If BOTH DEBEMAIL and DEBFULLNAME are set, PPA_MAINTAINER is constructed
    #     from DEB_EMAIL and DEBFULLNAME and Maintainer field is replaced with that
    #   - We extract the source package and build using debuild (WITH signing)
    #   - IFF dpkg-source -x and debuild was successful:
    #       - If DPUT_PPA_NAME exists, dput is called using DPUT_PPA_NAME as repository name
    #           ASSUMING ~/.dput.cf is setup correctly

    local PPA_MAINTAINER=""
    if [ -n "$DEBEMAIL" -a -n "$DEBFULLNAME" ]; then
        PPA_MAINTAINER="$DEBFULLNAME <${DEBEMAIL}>"
    fi

    show_timing_msg "$START_END_TIME_FILEPATH" "Source package build start" "yestee" ""; SECONDS=0
    local HOST_ARCH=$(dpkg-architecture | grep '^DEB_BUILD_ARCH=' | cut -d= -f2)
    # Put a divider in compile.out
    echo "" >> "${COMPILE_OUT_FILEPATH}"
    echo "--------------------------------------------------------------------------" >> "${COMPILE_OUT_FILEPATH}"

    # All the action from now is in ${DEB_DIR}
    cd "${DEB_DIR}"

    # Make a new directory for source build
    SRC_BUILD_DIR="$(basename ${KB_SRC_PKG_DIR})"
    rm -rf "${SRC_BUILD_DIR}" && mkdir "${SRC_BUILD_DIR}"
    cd ${SRC_BUILD_DIR}
    for f in ${PPA_UPLOAD_DSC_FILE} ${PPA_UPLOAD_TAR_FILE} ${PPA_UPLOAD_DEBIAN_TAR_FILE} ${PPA_UPLOAD_DIFF_GZ_FILE}
    do
        if [ -n "$f" ]; then
            cp ../$f .
        fi
    done
    dpkg-source -x ${PPA_UPLOAD_DSC_FILE} linux 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    if [ $? -ne 0 ]; then
        echo "dpkg-source -x failed " >> "${COMPILE_OUT_FILEPATH}"
        cd "$DEB_DIR"
        return 1
    fi
    for f in ${PPA_UPLOAD_DSC_FILE} linux/debian/control
    do
        # Update Build-depends
        sed -i '/^Build-Depends: / s/$/, libelf-dev, libncurses5-dev, libssl-dev, libfile-fcntllock-perl, fakeroot, bison, flex/' $f
        # Update Maintainer
        if [ -n "$PPA_MAINTAINER" ]; then
            sed -i "s/^Maintainer: .*$/Maintainer: $PPA_MAINTAINER/" $f
        fi
    done
    
    # Write a more comprehensive changelog
    if [ -x "$WRITE_CHANGELOG_SCRIPT" ]; then
        oldpwd=$(pwd)
        cd "$BUILD_DIR"
        $WRITE_CHANGELOG_SCRIPT
        cat debian/changelog >>"${COMPILE_OUT_FILEPATH}"
        cd "$oldpwd"
    else
        echo "WRITE_CHANGELOG_SCRIPT not found: $WRITE_CHANGELOG_SCRIPT"
    fi

    BUILD_OPTS="-S -a $HOST_ARCH "
    if [ -n "$GPG_KEYID" -o -n "$GPG_DEFAULT_KEY_SET" ]; then
        if [ -n "$GPG_KEYID" ]; then
            echo "Using GPG KeyID ${GPG_KEYID}"
            BUILD_OPTS="$BUILD_OPTS -k${GPG_KEYID}"
            # Also set DEB_SIGN_KEYID and export
            export DEB_SIGN_KEYID=${GPG_KEYID}
        else
            echo "Assuming default-key is set in gpg.conf"
        fi
    else
        BUILD_OPTS="$BUILD_OPTS -us -uc"
        echo "GPG_KEYID not set. Not signing source or changes. This cannot be uploaded to Launchpad.net"
    fi
    cd linux
    if [ -n "$PPA_MAINTAINER" ]; then
        dpkg-buildpackage $BUILD_OPTS -e"$PPA_MAINTAINER" -m"$PPA_MAINTAINER" 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    else
        dpkg-buildpackage $BUILD_OPTS 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    fi
    if [ $? -ne 0 ]; then
        echo "dpkg-buildpackage -S failed " >> "${COMPILE_OUT_FILEPATH}"
        cd "$DEB_DIR"
        return 1
    fi
    cd ..

    show_timing_msg "$START_END_TIME_FILEPATH" "Source package build finished" "yestee" "$(get_hms)"
    return 0
}

function ppa_upload_upload_src_to_ppa {
    if [ -z "$DPUT_PPA_NAME" ]; then
        return 0
    fi
    show_timing_msg "$START_END_TIME_FILEPATH" "Source package upload start" "yestee" ""; SECONDS=0
    # Put a divider in compile.out
    echo "" >> "${COMPILE_OUT_FILEPATH}"
    echo "--------------------------------------------------------------------------" >> "${COMPILE_OUT_FILEPATH}"
    cd "${DEB_DIR}"/"${SRC_BUILD_DIR}"
    SRC_CHANGE_FILE=$(ls -1 linux-*_source.changes | head -1)
    SRC_CHANGE_FILE=$(basename $SRC_CHANGE_FILE)
    if [ -z "$SRC_CHANGE_FILE" ]; then          # Unexpected
        echo "SRC_CHANGE_FILE not found" >> "${COMPILE_OUT_FILEPATH}"
        show_timing_msg "$START_END_TIME_FILEPATH" "Source package upload abandoned" "yestee" ""
        return 1
    fi
    cat "$SRC_CHANGE_FILE" >>"${COMPILE_OUT_FILEPATH}"
    echo "dput $DPUT_PPA_NAME $SRC_CHANGE_FILE" >>"${COMPILE_OUT_FILEPATH}"
    dput "$DPUT_PPA_NAME" "$SRC_CHANGE_FILE"
    show_timing_msg "$START_END_TIME_FILEPATH" "Source package upload finished" "yestee" "$(get_hms)"

    # Now upload the metapackages 
    if [ -n "$METAPKG_BUILD_DIR" -a -d "$METAPKG_BUILD_DIR" ]; then
        echo ""
        echo "--------- Uploading metapackages to Launchpad ----------"
        echo ""
        cd "$METAPKG_BUILD_DIR"
        for f in *_source.changes
        do
            echo "Uploading $f"
            dput "$DPUT_PPA_NAME" "$f"
        done
    else
        echo "METAPKG_BUILD_DIR not set or not a directory: $METAPKG_BUILD_DIR"
        echo "Not uploading metapackages to Launchpad"
    fi
}


#-------------------------------------------------------------------------
# functions for reupload_to_ppa.sh
#-------------------------------------------------------------------------


function reupload_set_vars() {
   DUMMY_VISUAL_SCRIPT=${SCRIPT_DIR}/dummy_visual.sh 
   if [ ! -x "$DUMMY_VISUAL_SCRIPT" ]; then
       echo "Script not found or not executable: $DUMMY_VISUAL_SCRIPT"
       return 1
   fi
}

function reupload_rebuild_src_pkg() {
    local changelog_msg="$@"
    if [ -z "$changelog_msg" ]; then
        changelog_msg="Automatic version increment - no changelog"
    fi
    local PPA_MAINTAINER=""
    if [ -n "$DEBEMAIL" -a -n "$DEBFULLNAME" ]; then
        PPA_MAINTAINER="$DEBFULLNAME <${DEBEMAIL}>"
    fi

    oldpwd=$(pwd)

    cd $DEB_DIR/${KB_SRC_PKG_DIR}
    if [ $? -ne 0 ]; then
        echo "Directory not found: $DEB_DIR/${KB_SRC_PKG_DIR}"
        return 1
    fi

    if [ -n "$GPG_KEYID" -o -n "$GPG_DEFAULT_KEY_SET" ]; then
        if [ -n "$GPG_KEYID" ]; then
            echo "Using GPG KeyID ${GPG_KEYID}"
            # Also set DEB_SIGN_KEYID and export
            export DEB_SIGN_KEYID=${GPG_KEYID}
        else
            echo "Assuming default-key is set in gpg.conf"
        fi
    else
        echo "GPG_KEYID not set. Not signing source or changes. This cannot be uploaded to Launchpad.net"
        return 1
    fi

    echo "You will have to enter your passphrase for signing source package"
    show_timing_msg "$START_END_TIME_FILEPATH" "Source package rebuild start" "yestee" ""; SECONDS=0
    \rm -f *.diff.gz *.dsc *_source.build *_source.changes *.upload
    cd $DEB_DIR/${KB_SRC_PKG_DIR}/linux
    if [ $? -ne 0 ]; then
        echo "Directory not found: $DEB_DIR/${KB_SRC_PKG_DIR}"
        return 1
    fi
    echo "" >> "${COMPILE_OUT_FILEPATH}"
    echo "--------------------------------------------------------------------------" >> "${COMPILE_OUT_FILEPATH}"

    VISUAL=$DUMMY_VISUAL_SCRIPT dch -i "$changelog_msg"
    VISUAL=$DUMMY_VISUAL_SCRIPT dch -r
    debuild -S -e"$PPA_MAINTAINER" 1>> "${COMPILE_OUT_FILEPATH}" || return 1 
    show_timing_msg "$START_END_TIME_FILEPATH" "Source package rebuild finished" "yestee" "$(get_hms)"

    cd $oldpwd
}

function reupload_upload_src_to_ppa() {
    if [ -z "$DPUT_PPA_NAME" ]; then
        return 0
    fi
    show_timing_msg "$START_END_TIME_FILEPATH" "Source package upload start" "yestee" ""; SECONDS=0
    echo "" >> "${COMPILE_OUT_FILEPATH}"
    echo "--------------------------------------------------------------------------" >> "${COMPILE_OUT_FILEPATH}"
    cd $DEB_DIR/${KB_SRC_PKG_DIR}
    SRC_CHANGE_FILE=$(ls -1 linux-*_source.changes | head -1)
    SRC_CHANGE_FILE=$(basename $SRC_CHANGE_FILE)
    if [ -z "$SRC_CHANGE_FILE" ]; then          # Unexpected
        echo "SRC_CHANGE_FILE not found" >> "${COMPILE_OUT_FILEPATH}"
        show_timing_msg "$START_END_TIME_FILEPATH" "Source package upload abandoned" "yestee" ""
        return 1
    fi
    cat "$SRC_CHANGE_FILE" >>"${COMPILE_OUT_FILEPATH}"
    echo "dput $DPUT_PPA_NAME $SRC_CHANGE_FILE" >>"${COMPILE_OUT_FILEPATH}"
    dput "$DPUT_PPA_NAME" "$SRC_CHANGE_FILE"

    show_timing_msg "$START_END_TIME_FILEPATH" "Source package upload finished" "yestee" "$(get_hms)"
}




#-------------------------------------------------------------------------
# Initiatilization steps after this
#-------------------------------------------------------------------------
if [ "$1" = "-h" -o "$1" = "--help" ]; then
    show_help
    exit 0
fi
set_vars
show_vars
$CHECK_REQD_PKGS_SCRIPT || exit 1
