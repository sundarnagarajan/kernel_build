#!/bin/bash
REQD_PKGS="gnupg dpkg-dev dh-make equivs"

$(dirname $0)/pkgs_missing_from.sh $REQD_PKGS
