#!/bin/bash
# ython3-paramiko dependency of dput is undocumented and appeared
# in ubuntu bionic 18.04
REQD_PKGS="gnupg dpkg-dev dput python3-paramiko"

$(dirname $0)/pkgs_missing_from.sh $REQD_PKGS
