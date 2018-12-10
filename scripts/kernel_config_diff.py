#!/usr/bin/env python2
import sys
import os
from collections import OrderedDict

if len(sys.argv) not in [3, 4]:
    print('Usage: %s <file_path_1> <file_path_2>' % (sys.argv[0],))
    exit(1)


def config_to_dict(cfg):
    '''
    cfg-->str: path to config file
    Returns-->OrderedDict with uncommented config values
    '''
    try:
        s = open(cfg, 'r').read()
    except:
        print('Error reading %s' % (cfg,))
        exit(1)
    d = OrderedDict()
    for l in s.splitlines():
        if l.startswith('#'):
            continue
        if l.strip() == '':
            continue
        if '=' not in l:
            print('Unrecognized line in %s:    %s' % (cfg, l))
            continue
        (k, v) = l.split('=', 1)
        d[k] = v
    return d


def compare_dicts(d1, d2):
    '''
    d1, d2-->dict
    Returns-->(l1, l2, l3-->list)
        l1-->list of str: key=value pairs ONLY in d1
        l2-->list of str: key=value pairs ONLY in d2
        l3-->list of tuples (kv1, kv2):
            kv1-->str: key=value in d1 where different in d2
            kv2-->str: key=value in d1 where different in d1
    '''
    l1 = []
    l2 = []
    l3 = []

    for (k, v) in d1.items():
        if k not in d2:
            l1.append('%s=%s' % (k, v))
        elif v != d2[k]:
            l3.append(('%s=%s' % (k, v), '%s=%s' % (k, d2[k])))

    for (k, v) in d2.items():
        if k not in d1:
            l2.append('%s=%s' % (k, v))
    return (l1, l2, l3)


def get_screen_width():
    '''
    Returns-->int: width in chars
    '''
    rows, columns = os.popen('stty size', 'r').read().split()
    return int(rows)


def compare_configs(cfg1, cfg2, show='all'):
    '''
    cfg1, cfg2-->str: paths to config files
    show-->str: one of [left, right, diff, all]
        left: Only show config values in first config (cfg1)
        right: Only show config values in second config (cfg2)
        diff: show only differing config values
        all: show all of the above (default)
    Prints differences to stdout
    '''
    if show not in ['left', 'right', 'diff', 'all']:
        print('Ignoring unknown choice: %s: ' % (show,))
        show = 'all'

    (d1, d2) = (config_to_dict(cfg1), config_to_dict(cfg2))
    (l1, l2, l3) = compare_dicts(d1, d2)
    if (l1, l2, l3) == ([], [], []):
        print('Config files are identical')
        return
    if show in ['all', 'left'] and l1:
        print('Only in config1: %s' % (cfg1,))
        for s in l1:
            print('    %s' % (s,))
    if show in ['all', 'right'] and l2:
        print('Only in config2: %s' % (cfg2,))
        for s in l2:
            print('    %s' % (s,))

    if show in ['diff', 'all'] and l3:
        try:
            w = get_screen_width()
            f1 = max(1, (w - 4) / 2)
        except:
            f1 = 1
        fmt = '    %%-%ds %%s' % (f1,)
        print('Differing config values:')
        for (c1, c2) in l3:
            print(fmt % (c1, c2))


if __name__ == '__main__':
    if len(sys.argv) > 3:
        show = sys.argv[3]
    else:
        show = 'all'
    compare_configs(sys.argv[1], sys.argv[2], show=show)
