#!/usr/bin/env python3
# Works in Python 2|3
'''
Following environment variables can be set to override default logic:
    KERNEL_CONFIG    : FULL PATH to existing config file
                       Will override config.kernel ../config
    KERNEL_VERSION   : Will override version from config file
                       Will filter available kernels
    KERNEL_TYPE      : Will filter available kernels
                       IGNORED if it is not a recognized type:
                           latest|mainline|stable|longterm

Default logic:
    - Kernel version is set from existing config file
    - Descending order of perference of kernel types:
        - latest
        - mainline
        - stable
        - longterm
    - By default will only choose major version same as config
        Can override with KERNEL_VERSION
    - By default will use config.kernel in ../config
        Can override with KERNEL_CONFIG
    - By default will choose first matching kernel, in descending order
        of preference of kernel type as above.
        Can override (filter) with KERNEL_TYPE
'''

from choose_kernel import get_chosen_kernel_url

kurl = get_chosen_kernel_url(verbose=False)
if kurl:
    # .0 versions show up on kernel.org JSON API without .0 subversion
    # This breaks matapackage --> kernel package dependency - since
    # we use show_chosen_url.py to create metapackages BEFORE
    # downloading kernel
    kver = kurl.kver
    if len(kver.split('.')) < 3:
        kver += '.0'
    print(kver)
else:
    exit(1)
