#!/bin/bash
REQD_PKGS="util-linux git build-essential fakeroot libncurses5-dev libssl-dev ccache libfile-fcntllock-perl curl libelf-dev bison flex rsync"

$(dirname $0)/pkgs_missing_from.sh $REQD_PKGS
