#!/bin/bash
REQD_PKGS="gnupg dpkg-dev dput"

$(dirname $0)/pkgs_missing_from.sh $REQD_PKGS
