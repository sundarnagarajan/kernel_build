#!/usr/bin/env python
'''
Following environment variables can be set to override default logic:
    KERNEL_CONFIG    : FULL PATH to existing config file
                       Will override config.kernel in ../config
    - By default will use config.kernel in ../config
        Can override with KERNEL_CONFIG
'''
from choose_kernel import get_config_version


cver = get_config_version(verbose=True)
if cver:
    print('Config seems to be from version %s' % (cver,))
