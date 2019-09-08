#!/usr/bin/env python3
# Works in Python 2|3
'''
Outputs MAJOR VERSION (ONLY) of latest kernel
Examples:
    Latest version number           Will output
    4.20                            4.20
    4.20.7                          4.20
    5.0                             5.0
    5.0.2                           5.0
    5.0.0                           5.0
'''

from kernel_url import get_kernel_urls, filter_kernel_urls


l = get_kernel_urls()
k = filter_kernel_urls(l, ktype='latest')
ver_splits = k.kver.split('.')
ret = '.'.join(ver_splits[:2])
print(ret)
