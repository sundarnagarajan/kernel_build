#!/bin/bash
#-------------------------------------------------------------------------
# Following are plain filenames - expected in same dir as this script
#-------------------------------------------------------------------------
# Kernel config file - unless KERNEL_CONFIG env var is set
# Can be overridden by KERNEL_CONFIG env var
CONFIG_FILE=config.kernel

# Patch file - all patches expected to be in one file
# Can be overridden by KERNEL_PATCHES env var
PATCH_FILE=all_patches.patch

#-------------------------------------------------------------------------
# Following are debug outputs - will be created in DEB_DIR
# Filenames cannot be overridden by environment vars
#-------------------------------------------------------------------------
# Output of build_kernel (ONLY)
COMPILE_OUT_FILENAME=compile.out
# Output of make silentoldconfig (ONLY)
SILENTCONFIG_OUT_FILENAME=silentconfig.out
# Output of ANSWER_QUESTIONS_SCRIPT - answers chosen
CHOSEN_OUT_FILENAME=chosen.out
# File containing time taken for different steps
START_END_TIME_FILE=start_end.out

#-------------------------------------------------------------------------
# Following are requried scripts - must be in same dir as this script
# Cannot be overridden by environment vars
#-------------------------------------------------------------------------
KERNEL_SOURCE_SCRIPT=get_kernel_source_url.py
SHOW_AVAIL_KERNELS_SCRIPT=show_available_kernels.py
UPDATE_CONFIG_SCRIPT=update_kernel_config.py
CHECK_REQD_PKGS_SCRIPT=required_pkgs.sh

# Kernel image build target
IMAGE_NAME=bzImage

#-------------------------------------------------------------------------
# Probably don't have to change anything below this
#-------------------------------------------------------------------------

SCRIPT_DIR="$(readlink -f $(dirname $0))"

#-------------------------------------------------------------------------
# functions
#-------------------------------------------------------------------------
function show_help {
    # If pandoc is available, use it to convert README.md to text
    which pandoc 1>/dev/null 2>&1
    if [ $? -eq 0 ]; then
        pandoc -r markdown_github -w plain "${SCRIPT_DIR}/README.md"
    fi
    # No pandoc
    if [ -f "${SCRIPT_DIR}/README" ]; then
        cat "${SCRIPT_DIR}/README"
    else
        cat "${SCRIPT_DIR}/README.md"
    fi
}

function choose_deb_dir {
    # If KERNEL_BUILD_DIR env var is set, set DEB_DIR to that dir
    # All components of KERNEL_BUILD_DIR except last component must already exist
    # If last component of KERNEL_BUILD_DIR doesn't exist, it is created
    # If KERNEL_BUILD_DIR is not set or All components of KERNEL_BUILD_DIR
    # except last component do not exist, DEB_DIR is set to 
    # ${CURDIR}/debs
    #
    # KERNEL_BUILD_DIR (any path component) canot contain spaces or colons
    # This is a limitation of the Linux kernel Makefile - you will get an error
    # that looks like:
    # Makefile:128: *** main directory cannot contain spaces nor colons.  Stop.

    CURDIR="$(readlink -f $PWD)"
    unset DEB_DIR
    BAD_DIR_MSG="Linux kernel cannot be built under a path containing spaces or colons
This is a limitation of the Linux kernel Makefile - you will get an error
that looks like:
  Makefile:128: *** main directory cannot contain spaces nor colons.  Stop."

    if [ -n "${KERNEL_BUILD_DIR}" ]; then
        case "${KERNEL_BUILD_DIR}" in
                *\ * )
                    echo "$BAD_DIR_MSG"
                    exit 1
                    ;;
                *:* )
                    echo "$BAD_DIR_MSG"
                    exit 1
                    ;;
        esac

        KERNEL_BUILD_DIR=$(readlink -f "${KERNEL_BUILD_DIR}")
        BUILD_DIR_PARENT=$(dirname "${KERNEL_BUILD_DIR}")
        if [ -d "${BUILD_DIR_PARENT}" ]; then
            if [ -e "${KERNEL_BUILD_DIR}" ]; then
                if [ ! -d "${KERNEL_BUILD_DIR}" ]; then
                    \rm -f "${KERNEL_BUILD_DIR}"
                    if [ $? -ne 0 ]; then
                        echo "Could not delete non-directory ${KERNEL_BUILD_DIR}"
                        exit 1
                    fi
                    mkdir -p "${KERNEL_BUILD_DIR}"
                    if [ $? -ne 0 ]; then
                        echo "Could not create ${KERNEL_BUILD_DIR}"
                        exit 1
                    fi
                else    # KERNEL_BUILD_DIR is an existing dir
                    find "${KERNEL_BUILD_DIR}" -mindepth 1 -delete
                    if [ $? -ne 0 ]; then
                        echo "Could not empty ${KERNEL_BUILD_DIR}"
                        exit 1
                    fi
                fi
            else
                mkdir -p "${KERNEL_BUILD_DIR}"
                if [ $? -ne 0 ]; then
                    echo "Could not create ${KERNEL_BUILD_DIR}"
                    exit 1
                fi
            fi
            DEB_DIR="${KERNEL_BUILD_DIR}"
            printf "%-24s : %s\n" "Building in" "${KERNEL_BUILD_DIR}"
        else
            echo "Parent directory does not exist: ${BUILD_DIR_PARENT}"
            echo "Ignoring KERNEL_BUILD_DIR: ${KERNEL_BUILD_DIR}"
        fi

    fi
    if [ -z "${DEB_DIR}" ]; then
        DEB_DIR="${CURDIR}/debs"
        case "${KERNEL_BUILD_DIR}" in
                *\ * )
                    echo "$BAD_DIR_MSG"
                    exit 1
                    ;;
                *:* )
                    echo "$BAD_DIR_MSG"
                    exit 1
                    ;;
        esac
        rm -rf "${DEB_DIR}"
        mkdir "${DEB_DIR}"
    fi
}

function set_vars {
    #-------------------------------------------------------------------------
    # Strip off directory path components if we expect only filenames
    #-------------------------------------------------------------------------
    CONFIG_FILE=$(basename "$CONFIG_FILE")
    PATCH_FILE=$(basename "$PATCH_FILE")

    KERNEL_SOURCE_SCRIPT=$(basename "$KERNEL_SOURCE_SCRIPT")
    SHOW_AVAIL_KERNELS_SCRIPT=$(basename "$SHOW_AVAIL_KERNELS_SCRIPT")
    UPDATE_CONFIG_SCRIPT=$(basename "$UPDATE_CONFIG_SCRIPT")
    CHECK_REQD_PKGS_SCRIPT=$(basename "$CHECK_REQD_PKGS_SCRIPT")

    COMPILE_OUT_FILENAME=$(basename "$COMPILE_OUT_FILENAME")
    SILENTCONFIG_OUT_FILENAME=$(basename "$SILENTCONFIG_OUT_FILENAME")
    CHOSEN_OUT_FILENAME=$(basename "$CHOSEN_OUT_FILENAME")
    START_END_TIME_FILE=$(basename "$START_END_TIME_FILE")

    # Required scripts can ONLY be in the same dir as this script
    KERNEL_SOURCE_SCRIPT="${SCRIPT_DIR}/${KERNEL_SOURCE_SCRIPT}"
    SHOW_AVAIL_KERNELS_SCRIPT="${SCRIPT_DIR}/${SHOW_AVAIL_KERNELS_SCRIPT}"
    UPDATE_CONFIG_SCRIPT="${SCRIPT_DIR}/${UPDATE_CONFIG_SCRIPT}"
    CHECK_REQD_PKGS_SCRIPT="${SCRIPT_DIR}/${CHECK_REQD_PKGS_SCRIPT}"

    # DEB_DIR set in separate function because it has more complex logic
    choose_deb_dir

    # Debug outputs are always in DEB_DIR
    SILENTCONFIG_OUT_FILEPATH="${DEB_DIR}/${SILENTCONFIG_OUT_FILENAME}"
    CHOSEN_OUT_FILEPATH="${DEB_DIR}/${CHOSEN_OUT_FILENAME}"
    COMPILE_OUT_FILEPATH="${DEB_DIR}/${COMPILE_OUT_FILENAME}"
    START_END_TIME_FILEPATH="${DEB_DIR}/$START_END_TIME_FILE"

    # CONFIG_FILE, PATCH_FILE and KERNEL_CONFIG_PREFS can be overridden by
    #  environment variables
    CONFIG_FILE_PATH="${SCRIPT_DIR}/${CONFIG_FILE}"
    if [ -n "$KERNEL_CONFIG" ]; then
        KERNEL_CONFIG=$(readlink -f "${KERNEL_CONFIG}")
        if [ -f "$KERNEL_CONFIG" ] ; then
            CONFIG_FILE_PATH="${KERNEL_CONFIG}"
        else
            echo "Non-existent config : ${KERNEL_CONFIG}"
            exit 1
        fi
    fi
    PATCH_FILE_PATH="${SCRIPT_DIR}/${PATCH_FILE}"
    if [ -n "${KERNEL_PATCHES}" ]; then
        KERNEL_PATCHES=$(readlink -f "${KERNEL_PATCHES}")
        if [ -f "${KERNEL_PATCHES}" ] ; then
            PATCH_FILE_PATH="${KERNEL_PATCHES}"
        else
            echo "Ignoring non-existent patch file : ${KERNEL_PATCHES}"
            unset PATCH_FILE_PATH
        fi
    fi
    if [ -n "${KERNEL_CONFIG_PREFS}" ]; then
        KERNEL_CONFIG_PREFS=$(readlink -f "${KERNEL_CONFIG_PREFS}")
        if [ ! -f "${KERNEL_CONFIG_PREFS}" ] ; then
            echo "Ignoring non-existent config prefs : ${KERNEL_CONFIG_PREFS}"
            unset KERNEL_CONFIG_PREFS
        fi
    else
        KERNEL_CONFIG_PREFS="${SCRIPT_DIR}/config.prefs"
    fi

    # Fix NUM_THREADS to be min(NUM_THREADS, number_of_cores)
    local NUM_CORES=$(lscpu | grep '^CPU(s)' | awk '{print $2}')
    local TARGETED_CORES=$(($NUM_CORES - 1))
    if [ $TARGETED_CORES -lt 1 ]; then
        TARGETED_CORES=1
    fi

    if [ -n "$NUM_THREADS" ]; then
        echo "$NUM_THREADS" | grep -q '^[1-9][0-9]*$'
        if [ $? -eq 0 ]; then
            if [ $NUM_THREADS -gt $TARGETED_CORES ]; then
                echo "Ignoring NUM_THREADS > (available cores - 1) ($TARGETED_CORES)"
                unset NUM_THREADS
            fi
        else
            echo "Ignoring invalid value for NUM_THREADS : $NUM_THREADS"
            unset NUM_THREADS
        fi
    fi
    if [ -z "$NUM_THREADS" ]; then
        NUM_THREADS=$TARGETED_CORES
    fi

    MAKE_THREADED="make -j$NUM_THREADS"
    INDENT="    "

    # Print what we are using
    printf "%-24s : %s\n" "Config file" "${CONFIG_FILE_PATH}"
    printf "%-24s : %s\n" "Patch file" "${PATCH_FILE_PATH}"
    printf "%-24s : %s\n" "Config prefs" "${KERNEL_CONFIG_PREFS}"
    printf "%-24s : %s\n" "Threads" "${NUM_THREADS}"
    printf "%-24s : %s\n" "DEBS built in" "${DEB_DIR}"
    printf "%-24s : %s\n" "silentoldconfig output" "$SILENTCONFIG_OUT_FILEPATH"
    printf "%-24s : %s\n" "Config choices output" "$CHOSEN_OUT_FILEPATH"
    printf "%-24s : %s\n" "Build output" "$COMPILE_OUT_FILEPATH"


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
    # $1: Message
    # $2: tee or not: 'yestee' implies tee
    # $3 (optional): elapsed time (string)
    if [ "$2" = "yestee" ]; then
        if [ -n "$3" ]; then
            printf "%-39s: %-28s (%s)\n" "$1" "$(date)" "$3" | tee -a "$START_END_TIME_FILEPATH"
        else
            printf "%-39s: %-28s\n" "$1" "$(date)" | tee -a "$START_END_TIME_FILEPATH"
        fi
    else
        if [ -n "$3" ]; then
            printf "%-39s: %-28s (%s)\n" "$1" "$(date)" "$3" >> "$START_END_TIME_FILEPATH"
        else
            printf "%-39s: %-28s\n" "$1" "$(date)" >> "$START_END_TIME_FILEPATH"
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
			exit 1
			;;
	esac
}

function get_kernel_source {
    show_timing_msg "Retrieve kernel source start" "yestee"
    SECONDS=0

    # Retrieve and extract kernel source
    if [ ! -x "${KERNEL_SOURCE_SCRIPT}" ]; then
        echo "Kernel source script not found: ${KERNEL_SOURCE_SCRIPT}"
        exit 1
    fi
    local KERNEL_SOURCE_URL="$(${KERNEL_SOURCE_SCRIPT})"
    # Check URL is OK:
    curl -s -f -I "$KERNEL_SOURCE_URL" 1>/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "URL not accessible: $KERNEL_SOURCE_URL"
        exit 1
    fi
    local TAR_FMT_IND=$(get_tar_fmt_ind "$KERNEL_SOURCE_URL")
    wget -q -O - -nd "$KERNEL_SOURCE_URL" | tar "${TAR_FMT_IND}xf" - -C "${DEB_DIR}"
    show_timing_msg "Retrieve kernel source finished" "yestee" "$(get_hms)"
}

function is_linux_kernel_source()
{
    # $1: kernel directory containing Makefile
    # Returns: 0 if it looks like linux kernel Makefile
    #          1 otherwise
    local help_out=$(make -s -C "$1" help)
    if [ $? -ne 0 ]; then
        return 1
    fi
    for target in clean mrproper distclean config menuconfig xconfig oldconfig defconfig silentoldconfig modules_install modules_prepare kernelversion kernelrelease install
    do
        echo "$help_out" | grep -q "^[[:space:]][[:space:]]*$target[[:space:]][[:space:]]*-[[:space:]]"
        if [ $? -ne 0 ]; then
            return 1
        fi
    done
    return 0
}

function kernel_version()
{
    # $1: kernel directory containing Makefile
    #     May be:
    #         - Kernel build directory
    #         - /lib/modules/<kern_ver>/build
    #
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

function set_build_dir {
    # Check there is exactly one dir extracted - we depend on this
    cd "${DEB_DIR}"
    if [ $(ls -1 | fgrep -v $(basename ${START_END_TIME_FILE}) | wc -l) -ne 1 ]; then
        echo "Multiple top-level dir extracted - almost certainly wrong"
        exit 1
    fi
    BUILD_DIR=$(echo "${DEB_DIR}/$(ls | head -1)")
    cd "${SCRIPT_DIR}"

    if [ ! -d "$BUILD_DIR" ]; then
        echo "Directory not found: BUILD_DIR: $BUILD_DIR"
        exit 1
    fi
    local KERN_VER=$(kernel_version "${BUILD_DIR}")
    if [ $? -ne 0 ]; then
        echo "Does not look like linux kernel source"
        exit 1
    fi

    echo "Building kernel $KERN_VER in ${BUILD_DIR}"
}

function apply_patches {
    if [ -n "$PATCH_FILE_PATH" ]; then
        if [ -f "${PATCH_FILE_PATH}" ]; then
            echo "Applying patches from ${PATCH_FILE_PATH}"
            cd "${BUILD_DIR}"
            patch -p1 < "${PATCH_FILE_PATH}" 2>&1 | sed -e "s/^/${INDENT}/"
            if [ $? -ne 0 ]; then
                echo "Patch failed" | sed -e "s/^/${INDENT}/"
                exit 1
            fi
        fi
    fi
}

function restore_kernel_config {
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
            exit 1
        fi
    fi
}

function run_make_silentoldconfig {
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
    # $ANSWER_QUESTIONS_SCRIPT
    if [ -z "$BUILD_DIR" ]; then
        echo "BUILD_DIR not set"
        exit 1
    fi
    if [ ! -d "$BUILD_DIR" ]; then
        echo "BUILD_DIR is not a directory: $BUILD_DIR"
        exit 1
    fi
    if [ ! -f "${BUILD_DIR}/.config" ]; then
        echo ".config not found: ${BUILD_DIR}/.config"
        exit 1
    fi
    if [ -z "$UPDATE_CONFIG_SCRIPT" ]; then
        echo "UPDATE_CONFIG_SCRIPT not set"
        exit 1
    fi
    if [ ! -x "$UPDATE_CONFIG_SCRIPT" ]; then
        echo "Not executable: $UPDATE_CONFIG_SCRIPT"
        exit 1
    fi
    local MAKE_CONFIG_CMD="make silentoldconfig"
    
    OLD_DIR="$(pwd)"
    cd "${BUILD_DIR}"
    PYTHONUNBUFFERED=yes $UPDATE_CONFIG_SCRIPT "${BUILD_DIR}" "${SILENTCONFIG_OUT_FILEPATH}" "${CHOSEN_OUT_FILEPATH}" "${MAKE_CONFIG_CMD}" "${KERNEL_CONFIG_PREFS}"
    ret=$?

    cd "$OLD_DIR"
    return $ret
}

function build_kernel {
    SECONDS=0
    \cp -f /dev/null "${COMPILE_OUT_FILEPATH}"
    local elapsed=''

    show_timing_msg "Kernel build start" "yestee" ""
    run_make_silentoldconfig
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && exit 1
    $MAKE_THREADED $IMAGE_NAME 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && exit 1
    show_timing_msg "Kernel $IMAGE_NAME build finished" "yestee" "$(get_hms)"

    show_timing_msg "Kernel modules build start" "notee" ""; SECONDS=0
    $MAKE_THREADED modules 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && exit 1
    show_timing_msg "Kernel modules build finished" "yestee" "$(get_hms)"

    show_timing_msg "Kernel deb build start" "notee" ""; SECONDS=0
    $MAKE_THREADED bindeb-pkg 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    [ $? -ne 0 ] && (tail -20 "${COMPILE_OUT_FILEPATH}"; echo ""; echo "See ${COMPILE_OUT_FILEPATH}") && exit 1

    show_timing_msg "Kernel deb build finished" "yestee" "$(get_hms)"
    show_timing_msg "Kernel build finished" "notee" ""

    echo "-------------------------- Kernel compile time -------------------------------"
    cat $START_END_TIME_FILEPATH
    echo "------------------------------------------------------------------------------"
    echo "Kernel DEBS: (in $(readlink -f $DEB_DIR))"
    cd "${DEB_DIR}"
    ls -1 *.deb | sed -e "s/^/${INDENT}/"
    echo "------------------------------------------------------------------------------"
    \rm -f "${COMPILE_OUT_FILEPATH}" "${DEB_DIR}/${SILENTCONFIG_OUT_FILEPATH}" "$START_END_TIME_FILEPATH"
}

#-------------------------------------------------------------------------
# Actual build steps after this
#-------------------------------------------------------------------------
if [ "$1" = "-h" -o "$1" = "--help" ]; then
    show_help
    exit 0
fi
set_vars
$CHECK_REQD_PKGS_SCRIPT | exit 1


rm -f "$START_END_TIME_FILEPATH"
# Show available kernels and kernel version of available config
if [ -x "${SHOW_AVAIL_KERNELS_SCRIPT}" ]; then
    $SHOW_AVAIL_KERNELS_SCRIPT
fi
    
get_kernel_source
set_build_dir
apply_patches
restore_kernel_config
build_kernel
