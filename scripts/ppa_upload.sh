#!/bin/bash
#-------------------------------------------------------------------------
# Following are debug outputs - will be created in DEB_DIR
# Filenames cannot be overridden by environment vars
#-------------------------------------------------------------------------
# Output of build_kernel (ONLY)
COMPILE_OUT_FILENAME=compile.out
# File containing time taken for different steps
START_END_TIME_FILE=start_end.out

#-------------------------------------------------------------------------
# Probably don't have to change anything below this
#-------------------------------------------------------------------------

SCRIPT_DIR="$(readlink -f $(dirname $0))"

#-------------------------------------------------------------------------
# Following are requried scripts - must be in same dir as this script
# Cannot be overridden by environment vars
#-------------------------------------------------------------------------
CHECK_REQD_PKGS_SCRIPT=upload_required_pkgs.sh

#-------------------------------------------------------------------------
# functions
#-------------------------------------------------------------------------

function read_config {
    #-------------------------------------------------------------------------
    # Use KBUILD_CONFIG to get environment variables
    # Use KERNEL_BUILD_CONFIG if set to choose config file - defaults to
    # ~/.kernel_build.config
    #-------------------------------------------------------------------------
    KBUILD_CONFIG=~/.kernel_build.config

    if [ -n "$KERNEL_BUILD_CONFIG" ]; then
        KBUILD_CONFIG=$KERNEL_BUILD_CONFIG
    fi
    if [ -f "$KBUILD_CONFIG" ]; then
        if [ -r "$KBUILD_CONFIG" ]; then
            . "$KBUILD_CONFIG"
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
}

function check_deb_dir {
    # Everything in this script depends on DEB_DIR being set, existing
    # and containing exactly one filename ending in .dsc
    # The rest of the checks are done by dpkg-source -x

    if [ -z "$DEB_DIR" ]; then
        echo "DEB_DIR not set, cannot proceed"
        return 1
    fi
    DEB_DIR=$(readlink -f "${DEB_DIR}")
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

function set_vars {
    #-------------------------------------------------------------------------
    # Strip off directory path components if we expect only filenames
    #-------------------------------------------------------------------------
    CHECK_REQD_PKGS_SCRIPT=$(basename "$CHECK_REQD_PKGS_SCRIPT")

    COMPILE_OUT_FILENAME=$(basename "$COMPILE_OUT_FILENAME")
    START_END_TIME_FILE=$(basename "$START_END_TIME_FILE")

    # Required scripts can ONLY be in the same dir as this script
    CHECK_REQD_PKGS_SCRIPT="${SCRIPT_DIR}/${CHECK_REQD_PKGS_SCRIPT}"

    # Debug outputs are always in DEB_DIR
    COMPILE_OUT_FILEPATH="${DEB_DIR}/${COMPILE_OUT_FILENAME}"
    START_END_TIME_FILEPATH="${DEB_DIR}/$START_END_TIME_FILE"

    INDENT="    "
    cd "${DEB_DIR}"

    DSC_FILE=$(ls -1 linux-*.dsc | head -1)
    TAR_FILE=$(ls -1 *.orig.tar.gz | head -1)
    DEBIAN_TAR_FILE=$(ls -1 *.debian.tar.gz | head -1)
    # Kernel 4.17.6 seems to have started using .diff.gz instead of .debian.tar.gz!
    DIFF_GZ_FILE=$(ls -1 linux-*.diff.gz | head -1)
    DSC_FILE=$(basename $DSC_FILE)
    TAR_FILE=$(basename $TAR_FILE)
    if [ -n "$DEBIAN_TAR_FILE" ]; then
        DEBIAN_TAR_FILE=$(basename $DEBIAN_TAR_FILE)
    fi
    if [ -n "$DIFF_GZ_FILE" ]; then
        DIFF_GZ_FILE=$(basename $DIFF_GZ_FILE)
    fi

    # Print what we are using
    printf "%-24s : %s\n" "DEBS built in" "${DEB_DIR}"
    printf "%-24s : %s\n" "DSC_FILE" "$DSC_FILE"
    printf "%-24s : %s\n" "TAR_FILE" "$TAR_FILE"
    printf "%-24s : %s\n" "DEBIAN_TAR_FILE" "$DEBIAN_TAR_FILE"
    printf "%-24s : %s\n" "DIFF_GZ_FILE" "$DIFF_GZ_FILE"
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

function build_src_changes {
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

    show_timing_msg "Source package build start" "yestee" ""; SECONDS=0
    local HOST_ARCH=$(dpkg-architecture | grep '^DEB_BUILD_ARCH=' | cut -d= -f2)
    # Put a divider in compile.out
    echo "" >> "${COMPILE_OUT_FILEPATH}"
    echo "--------------------------------------------------------------------------" >> "${COMPILE_OUT_FILEPATH}"

    # All the action from now is in ${DEB_DIR}
    cd "${DEB_DIR}"

    # Make a new directory for source build
    SRC_BUILD_DIR=$(mktemp -d -p .)
    cd ${SRC_BUILD_DIR}
    for f in ${DSC_FILE} ${TAR_FILE} ${DEBIAN_TAR_FILE} ${DIFF_GZ_FILE}
    do
        if [ -n "$f" ]; then
            cp ../$f .
        fi
    done
    dpkg-source -x ${DSC_FILE} linux 1>>"${COMPILE_OUT_FILEPATH}" 2>&1
    if [ $? -ne 0 ]; then
        echo "dpkg-source -x failed " >> "${COMPILE_OUT_FILEPATH}"
        cd "$DEB_DIR"
        return 1
    fi
    for f in ${DSC_FILE} linux/debian/control
    do
        # Update Build-depends
        sed -i '/^Build-Depends: / s/$/, libelf-dev, libncurses5-dev, libssl-dev, libfile-fcntllock-perl, fakeroot, bison/' $f
        # Update Maintainer
        if [ -n "$PPA_MAINTAINER" ]; then
            sed -i "s/^Maintainer: .*$/Maintainer: $PPA_MAINTAINER/" $f
        fi
    done

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

    show_timing_msg "Source package build finished" "yestee" "$(get_hms)"
    return 0
}

function upload_src_to_ppa {
    if [ -z "$DPUT_PPA_NAME" ]; then
        return 0
    fi
    show_timing_msg "Source package upload start" "yestee" ""; SECONDS=0
    # Put a divider in compile.out
    echo "" >> "${COMPILE_OUT_FILEPATH}"
    echo "--------------------------------------------------------------------------" >> "${COMPILE_OUT_FILEPATH}"
    cd "${DEB_DIR}"/"${SRC_BUILD_DIR}"
    SRC_CHANGE_FILE=$(ls -1 linux-*_source.changes | head -1)
    SRC_CHANGE_FILE=$(basename $SRC_CHANGE_FILE)
    if [ -z "$SRC_CHANGE_FILE" ]; then          # Unexpected
        echo "SRC_CHANGE_FILE not found" >> "${COMPILE_OUT_FILEPATH}"
        show_timing_msg "Source package upload abandoned" "yestee" ""
        return 1
    fi
    cat "$SRC_CHANGE_FILE" >>"${COMPILE_OUT_FILEPATH}"
    echo "dput $DPUT_PPA_NAME $SRC_CHANGE_FILE" >>"${COMPILE_OUT_FILEPATH}"
    dput "$DPUT_PPA_NAME" "$SRC_CHANGE_FILE"
    show_timing_msg "Source package upload finished" "yestee" "$(get_hms)"

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
# Actual build steps after this
#-------------------------------------------------------------------------
read_config || exit 1
check_deb_dir || exit 1
set_vars
$CHECK_REQD_PKGS_SCRIPT || exit 1

build_src_changes || exit 1
upload_src_to_ppa || exit 1



echo "-------------------------- Kernel compile time -------------------------------"
cat $START_END_TIME_FILEPATH
echo "------------------------------------------------------------------------------"
echo "Kernel DEBS: (in $(readlink -f $DEB_DIR))"
cd "${DEB_DIR}"
ls -1 *.deb | sed -e "s/^/${INDENT}/"
echo "------------------------------------------------------------------------------"

\rm -f "${COMPILE_OUT_FILEPATH}" "$START_END_TIME_FILEPATH"
