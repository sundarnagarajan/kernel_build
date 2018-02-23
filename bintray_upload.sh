#!/bin/bash

SCRIPT_DIR=$(readlink -e $(dirname $0))
BINTRAY_CONFIG=~/.bintray.config
KBUILD_CONFIG=~/.kernel_build.config

if [ -n "$KERNEL_BUILD_CONFIG" ]; then
    KBUILD_CONFIG=$KERNEL_BUILD_CONFIG
fi
if [ -f "$KBUILD_CONFIG" ]; then
    if [ -r "$KBUILD_CONFIG" ]; then
        . "$KBUILD_CONFIG"
        if [ $? -ne 0 ]; then
            echo "Error sourcing KERNEL_BUILD_CONFIG : $KBUILD_CONFIG"
            exit 1
        fi
    else
        echo "Ignoring unreadable KERNEL_BUILD_CONFIG : $KBUILD_CONFIG"
    fi
else
    echo "Ignoring missing KERNEL_BUILD_CONFIG : $KBUILD_CONFIG"
fi





if [ -n "$BINTRAY_CONFIG" ]; then
    if [ -f "$BINTRAY_CONFIG" ]; then
        if [ -r "$BINTRAY_CONFIG" ]; then
            . "$BINTRAY_CONFIG"
            if [ $? -ne 0 ]; then
                echo "Sourcing $BINTRAY_CONFIG failed"
                exit 1
            fi
        else
            echo "BINTRAY_CONFIG not readable: $BINTRAY_CONFIG"
        fi
    else
        echo "BINTRAY_CONFIG not found: $BINTRAY_CONFIG"
    fi
else
    echo "BINTRAY_CONFIG not set"
fi

# Check required elements are defined in BINTRAY_CONFIG
errors=0
if [ -z "$BINTRAY_USERNAME" ]; then
    echo "BINTRAY_USERNAME not set"
    errors=1
elif [ -z "$BINTRAY_API_KEY" ]; then
    echo "BINTRAY_API_KEY not set"
    errors=1
elif [ -z "$BINTRAY_REPOSITORY" ]; then
    echo "BINTRAY_REPOSITORY not set"
    errors=1
elif [ -z "$BINTRAY_DISTRIBUTIONS" ]; then
    echo "BINTRAY_DISTRIBUTIONS not set"
    errors=1
elif [ -z "$BINTRAY_ARCHITECTURES" ]; then
    echo "BINTRAY_ARCHITECTURES not set"
    errors=1
elif [ -z "$BINTRAY_COMPONENTS" ]; then
    echo "BINTRAY_COMPONENTS not set"
    errors=1
fi
if [ $errors -ne 0 ]; then
    exit 1
fi


if [ -n "$KERNEL_BUILD_DIR" ]; then
    DEB_DIR="$KERNEL_BUILD_DIR"
fi
if [ -z "$DEB_DIR" ]; then
    DEB_DIR=${SCRIPT_DIR}/build
fi
if [ ! -d "$DEB_DIR" ]; then
    echo "DEB_DIR not a directory: $DEB_DIR"
    exit 1
fi

function upload {
    # $1: deb file path
    DEB_FILE=$1
    PKG_FULL=$(dpkg-deb -f $1 Package)
    VER_FULL=$(dpkg-deb -f $1 Version)

    VERSION=${VER_FULL%-*}
    PACKAGE=${PKG_FULL%-${VERSION}}

    echo -n "${PACKAGE} (${VER_FULL}): "
    curl -T ${DEB_FILE} -u${BINTRAY_USERNAME}:${BINTRAY_API_KEY} "https://api.bintray.com/content/${BINTRAY_USERNAME}/${BINTRAY_REPOSITORY}/${PACKAGE}/${VER_FULL}/${DEB_FILE};deb_distribution=${BINTRAY_DISTRIBUTIONS};deb_component=${BINTRAY_COMPONENTS};deb_architecture=${BINTRAY_ARCHITECTURES};publish=1;override=1"
    echo ""
}

cd "$DEB_DIR"
for f in *.deb
do
    upload $f
done
