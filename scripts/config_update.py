#!/usr/bin/env python3

import sys
import os
from collections import OrderedDict
import re
import pexpect
import time
from collections import namedtuple
import subprocess
from pyutils import (
    DEFAULT_ENCODING,
    format_exc,
    file_contents,
    remove_blank_lines,
    FileWriteSingleton,
)


def answer_questions(cmd, out_file, chosen_out_file=None):
    '''
    cmd-->str: e.g. 'make oldconfig'
    out_file -->str: file containing output of cmd
    chosen_out_file-->str: path to chosen.out (debug output)
    '''
    def debug(f, s):
        f.write(s + '\n')
        f.flush()

    c = pexpect.spawn(cmd, encoding=DEFAULT_ENCODING, timeout=1)
    # print('Child process PID = %d' % (c.pid,))
    c.logfile = open(out_file, 'a+')
    if chosen_out_file:
        f = open(chosen_out_file, 'a+')
    else:
        f = sys.stdout

    pat_desc = '(?P<DESC>.*?)'
    pat_key = '\((?P<CONFIG_KEY>\S+)\)'
    pat_opts = '\[(?P<OPTS>\S+)]'
    pat_new = '\(NEW\)'
    pat = '^%s %s %s %s' % (pat_desc, pat_key, pat_opts, pat_new)

    question_patterns = [
        pexpect.EOF,
        pexpect.TIMEOUT,
        pat,
        '^\s*choice.*$',
    ]

    while not c.eof():
        ind = c.expect(question_patterns, timeout=2)
        if ind == 0:      # EOF
            break
        elif ind == 1:      # TIMEOUT
            c.sendline('')
            continue
        elif ind == 2:        # options to choose
            ans = ''
            if c.match:
                gd = c.match.groupdict()
                def_ans = [x for x in gd['OPTS'] if x in 'YNM']
                if def_ans:
                    def_ans = def_ans[0]
                else:
                    def_ans = 'UNKNOWN'
                if 'm' in gd['OPTS'].lower():
                    ans = 'm'
                    chosen = ans
                else:
                    chosen = def_ans
                desc = gd['DESC'].splitlines()[-1].strip('\r\n')
                debug(f, 'DESC: %s\nKEY: %s\nOPTS: %s\nANS: %s\n\n' % (
                    desc, gd['CONFIG_KEY'], gd['OPTS'], chosen
                ))
                c.sendline(ans)
            else:
                debug(
                    f,
                    'Unexpected error: index == 1, but c.match is None')
        elif ind == 3:          # choice
            debug(f, '--- CHOICE --- %s\n' % (c.after.splitlines()[-1],))
            c.sendline('')

    debug(f, '\n----- COMPLETED\n')

    ret = c.isalive()
    if ret is True:
        time.sleep(1)
        ret = c.isalive()
    return True


CfgVarNT = namedtuple('CfgVarNT', [
    'f',
    't', 'k', 'default', 'p',
    'default_str', 'sec',
])


LineNT = namedtuple(
    'LineNT',
    [
        'num', 'raw', 'stripped',
        'matched', 'valid',
        'lt', 'k', 'v',
    ]
)


class ChosenOutSingleton(FileWriteSingleton):
    pass


class KernelConfigVars(object):
    '''
    Kconfig language reference:
    https://www.kernel.org/doc/html/latest/kbuild/kconfig-language.html

    2 high-level ways to introduce a config variable:
        ^config \S+              e.g. config DRM_AMD_DC
        ^menuconfig \S+          e.g. menuconfig USB_SERIAL

    Variable types:
        bool | tristate | string | hex | int

    Default value:
        Kernel documentation (link above) CLEARLY specifies:
        "The default value deliberately defaults to ‘n’ in order to avoid
         bloating the build"

    Lines specifying default value:
        default | def_bool | def_tristate
    '''

    def __init__(self, kcu, syms=[]):
        '''
        kcu-->KernelConfigUpdater object
        syms-->list of str: CFG_KEYS. If syms is empty, ALL CFG_KEYs are considered
        '''
        self.kcu = kcu
        self.syms = syms
        self.build_dir = os.path.dirname(self.kcu.cfg)

    def __syms_2_grep_pat(self):
        '''
        Returns-->str
        If length of self.syms is large enough, concatenating them into a grep pattern
        will make the command line too long. In that case (checked with 'getconf ARG_MAX'
        this function will return ALL Kconfig files that define at least one symbol
        and filtering will (should) happen in __syms_2_re_pat
        '''
        ret = []
        l1 = ['config', 'menuconfig']
        if self.syms:
            l2 = self.syms
        else:
            l2 = ['\S+']
        for i in l1:
            for j in l2:
                ret.append('^%s %s$' % (i, j))
        ret = '|'.join(ret)
        if len(ret) > 4096:
            max_cmd_len = subprocess.check_output('getconf ARG_MAX', shell=True)
            max_cmd_len = int(max_cmd_len.decode(DEFAULT_ENCODING))
            if len(ret) < (max_cmd_len - 200):
                ret = []
                l2 = ['\S+']
                for i in l1:
                    for j in l2:
                        ret.append('^%s %s$' % (i, j))
                ret = '|'.join(ret)
        return ret

    def __kconfig_files(self):
        '''
        Returns-->list of str: Kconfig file paths UNDER self.build_dir
        Only those Kconfig files that contain '^config \S+ | ^menuconfig \S+'
        are returned - not all. There are ~24 Kconfig files without this pattern
        (ver 5.9-rc6) and none of them are relevant (checked manually)

        If length of self.syms is large enough, concatenating them into a grep pattern
        will make the command line too long. In that case (checked with 'getconf ARG_MAX'
        this function will return ALL Kconfig files that define at least one symbol
        and filtering will (should) happen in file_2_nt_dict
        '''
        oldpwd = os.getcwd()
        os.chdir(self.build_dir)

        grep_pat = self.__syms_2_grep_pat()
        cmd = "grep -Pl '%s' $(find -type f -name Kconfig)" % (grep_pat,)

        ret = []
        for f in subprocess.check_output(
            cmd, shell=True
        ).decode(DEFAULT_ENCODING).replace('\n', ' ').split(None):
            if f.startswith('./'):
                f = f[2:]
            ret.append(f)

        os.chdir(oldpwd)
        return ret

    def __kconfig_2_sections(self, s):
        '''
        s-->str: Kconfig file contents
        Returns-->list of str: sections starting with unindented non-space char
        '''
        ret = []
        lines = s.splitlines()
        start_match = re.compile('^\S+')
        blank_line_pat = '^\s*$'

        acc = []
        for l in lines:
            if re.match(start_match, l):
                # Little hack when type def or default line is not indented
                # but has no blank line above
                if acc and re.match(blank_line_pat, acc[-1]):
                    # push previous
                    if acc:
                        ret.append('\n'.join(acc))
                        acc = []
            acc.append(l)

        if acc:
            ret.append('\n'.join(acc))
        return [x for x in ret if x.strip()]

    def __file_2_nt_dict(self, f):
        '''
        f-->str: Kconfig file path
        Returns-->OrderedDict:
            key-->str: CFG_KEY
            val-->list of CfgVarNT
        '''
        oldpwd = os.getcwd()
        os.chdir(self.build_dir)

        key_pat = re.compile(
            '^(config|menuconfig)\s+(?P<CFG_KEY>\S+)',
            re.MULTILINE + re.DOTALL
        )
        type_prompt_pat = re.compile(
            '^\s+(?P<TYPE>bool|tristate|string|hex|int)\s*?(?P<PROMPT>.*?)$',
            re.MULTILINE,
        )
        unquote_pat = re.compile('^"(?P<QUOTED>.*?)"$')
        default_pat = re.compile(
            '^\s+(default|def_bool|def_tristate)\s+(?P<DEFAULT>.*$)$',
            re.MULTILINE,
        )
        type_default_pat = re.compile(
            '^\s+def_(?P<TYPE>bool|tristate)\s+(?P<DEFAULT>.*$)$',
            re.MULTILINE,
        )

        sec_pat = []
        l1 = ['config', 'menuconfig']
        if self.syms:
            l2 = self.syms
        else:
            l2 = ['\S+']
        for i in l1:
            for j in l2:
                sec_pat.append('^%s (%s).*?$' % (i, j))
        sec_pat = '|'.join(sec_pat)
        sec_pat = re.compile(sec_pat, re.MULTILINE + re.DOTALL)

        (fstr, _) = file_contents(f)
        secs = self.__kconfig_2_sections(fstr)

        t = None
        k = None
        p = None
        default = None
        default_str = None

        syms = dict.fromkeys(self.syms)
        ret = OrderedDict()
        for sec in secs:
            m = re.search(key_pat, sec)
            if not m:
                continue
            try:
                k = m.groupdict()['CFG_KEY']
            except Exception as e:
                continue
            if self.syms and k not in syms:
                continue
            m = re.search(type_prompt_pat, sec)
            if m:
                try:
                    t = m.groupdict()['TYPE']
                except:
                    pass
                try:
                    p = m.groupdict()['PROMPT']
                    m = re.search(unquote_pat, p)
                    if m:
                        try:
                            p = m.groupdict()['QUOTED']
                        except:
                            pass
                except:
                    pass
            m = re.search(default_pat, sec)
            if m:
                try:
                    default_str = m.groupdict()['DEFAULT']
                    m = re.search(unquote_pat, default_str)
                    if m:
                        try:
                            default_str = m.groupdict()['QUOTED']
                        except:
                            pass
                except:
                    pass
            # type and default may have been specified together
            # using def_bool or def_tristate
            if not t:
                m = re.search(type_default_pat, sec)
                if m:
                    try:
                        t = m.groupdict()['TYPE']
                    except:
                        pass
                    if not default_str:
                        try:
                            default_str = m.groupdict()['DEFAULT']
                            m = re.search(unquote_pat, default_str)
                            if m:
                                try:
                                    default_str = m.groupdict()['QUOTED']
                                except:
                                    pass
                        except:
                            pass
            if default_str in ['y', 'n', 'm']:
                default = default_str
            if t in ['string', 'int', 'hex']:
                default = default_str
            if not default_str:
                default = 'n'

            nt = CfgVarNT(
                f=f, k=k, t=t, p=p, sec=sec,
                default=default, default_str=default_str
            )

            if k in ret:
                ret[k] = ret[k] + [nt]
            else:
                ret[k] = [nt]

        os.chdir(oldpwd)
        return ret

    def kconfig_2_nt_dict(self, summarize=True, details=True):
        '''
        Returns-->OrderedDict:
            key-->str: CFG_KEY
            val-->list of CfgVarNT
        '''
        ret = OrderedDict()
        kconfig_files = self.__kconfig_files()

        for f in kconfig_files:
            ret1 = self.__file_2_nt_dict(f=f)
            for (k, v) in ret1.items():
                if k in ret:
                    ret[k] = ret[k] + ret1[k]
                else:
                    ret[k] = ret1[k]

        if summarize:
            if details:
                self.summarize(
                    d=ret, kconfig_files=kconfig_files,
                    not_found=True,
                    unknown_types=True,
                    multi_defs=True,
                    unknown_default=True,
                )
            else:
                self.summarize(
                    d=ret, kconfig_files=kconfig_files,
                    not_found=False,
                    unknown_types=False,
                    multi_defs=False,
                    unknown_default=False,
                )
        return ret

    def summarize(
        self, d, kconfig_files=[],
        not_found=True,
        unknown_types=True,
        multi_defs=False,
        unknown_default=False
    ):
        '''
        d-->OrderedDict as returned by kconfig_2_nt_dict
            key-->str: CFG_KEY
            val-->list of CfgVarNT
        kconfig_files-->list of str: Kconfig file paths under self.build_dir
        unknown_types-->bool: Show details of sections containing vars
            without explicit type definition statement
        multi_defs-->bool: Show Kconfig fie paths for vars defined in
            multiple Kconfig files
        unknown_default-->bool show default definition string for vars
            where default definition was present but could not be parsed
        '''
        syms_multi_def = []
        syms_not_found = []
        syms_unknown_type = []
        syms_no_default = []

        num_mult_defs = 0
        num_not_found = 0
        num_unknown_types = 0
        num_no_default = 0

        if self.syms:
            for k in self.syms:
                if k not in d:
                    num_not_found += 1
                    syms_not_found.append(k)

        for (k, v) in d.items():
            # Avoid false positives - ignore definitions in Kconfig files under 'arch/*'
            # or in Kconfig siles under 'scripts/kconfig/tests'
            x = [
                x for x in v if not x.f.startswith('arch') and
                not x.f.startswith('scripts/kconfig/tests')
            ]
            if len(x) > 1:
                num_mult_defs += 1
                syms_multi_def.append(k)

            found_type = False
            found_default = False

            for v1 in v:
                if v1.t is not None:
                    found_type = True
                if v1.default is not None:
                    found_default = True

            if not found_type:
                num_unknown_types += 1
                syms_unknown_type.append(k)
            if not found_default:
                num_no_default += 1
                syms_no_default.append(k)

        if self.syms:
            syms = str(len(self.syms))
        else:
            syms = 'ALL'
        print('%-35s : %s' % ('Input symbols', syms,))
        print('%-35s : %d' % ('Number of Kconfig files', len(kconfig_files)))
        if self.syms:
            print('%-35s : %d of %d' % (
                'Symbols found',
                len(d) - num_not_found, len(d)
            ))
            print('%-35s : %d' % ('Symbols not found', num_not_found,))
            if not_found:
                for k in syms_not_found:
                    print('    %s:' % (k,))
        else:
            print('%-35s : %d' % ('Symbols found', len(d) - num_not_found,))

        print('%-35s : %d' % ('Symbols with unknown type', num_unknown_types,))
        if num_unknown_types > 0 and unknown_types:
            for k in syms_unknown_type:
                print('    %s:' % (k,))
                for v1 in d[k]:
                    print('        %s' % (v1.f,))
                    sec = remove_blank_lines(v1.sec, remove_comments=True)
                    sec = '\n'.join([(' ' * 12) + x for x in sec.splitlines()])
                    print(sec)

        print('%-35s : %d' % ('Symbols with multiple definitions', num_mult_defs,))
        if num_mult_defs > 0 and multi_defs:
            for k in syms_multi_def:
                print('    %s:' % (k,))
                for v1 in d[k]:
                    print('        %s' % (v1.f,))
        if num_no_default > 0 and unknown_default:
            print('%-35s : %d' % (
                'Symbols with unknown default', num_no_default,
            ))
            for k in syms_no_default:
                print('    %s:' % (k,))
                for v1 in d[k]:
                    print('        (%s) : %s' % (
                        str(v1.t),
                        str(v1.default_str),
                    ))


class KernelConfigUpdater(object):
    LINE_INVALID = 0
    LINE_EMPTY = 1
    LINE_UNDEF_COMMENT = 2
    LINE_COMMENT = 3
    LINE_SET_KV = 4

    BLANK_LINE_PAT = '^\s*$'
    UNDEF_LINE_PAT = '^\s*#\s*(?P<CFG_KEY>\S+)\s+is not set$'
    COMMENT_LINE_PAT = '^\s*#'
    SET_LINE_PAT = '^(?P<CFG_KEY>\S+)\s*=\s*(?P<CFG_VAL>\S+.*?)$'

    def __init__(
        self, cfg, prefs_list=[], debug=sys.stderr,
        encoding='ascii', prefix='CONFIG_',
    ):
        '''
        cfg-->str: file path of linux kernel .config
        prefs_list-->list of str: paths of prefs files (format of config.prefs)
        debug-->str (file path) OR file-like object opened for writing / appending
            with a 'write' method
        encoding-->str
        prefix-->str: do not change this
        '''
        self.cfg = cfg
        self.prefs_list = prefs_list
        self.__config = 'CONFIG_'
        self.__debug_fd = ChosenOutSingleton(
            f=debug,
            encoding=DEFAULT_ENCODING,
            errors=sys.stderr,
            expanduser=True,
            expandvars=True
        )
        self.encoding = encoding
        self.__fstr = None
        self.__line_list = None
        self.__nt_list = None
        self.__cfg_dict = None
        self.__prefs_dict = None

    def debug(self, s):
        self.__debug_fd.write(s)

    @property
    def cfg_contents(self):
        '''Returns-->str: contents of cfg'''
        if self.__fstr is None:
            (self.__fstr, self.__encoding) = file_contents(
                self.cfg, debug=self.__debug_fd
            )
        return self.__fstr

    @property
    def cfg_line_list(self):
        '''Returns-->list of str: lines in cfg'''
        if self.__line_list is None:
            self.__line_list = self.cfg_contents.splitlines()
        return self.__line_list

    @property
    def cfg_nt_list(self):
        '''Returns-->list of LineNT'''
        if self.__nt_list is None:
            self.__nt_list = self.__line_list_2_nt_list(self.cfg_line_list)
        return self.__nt_list

    @property
    def cfg_dict(self):
        '''Returns-->OrderedDict'''
        if self.__cfg_dict is None:
            self.__cfg_dict = self.__nt_list_2_dict(self.cfg_nt_list)
        return self.__cfg_dict

    @property
    def prefs_dict(self):
        '''Returns-->OrderedDict'''
        if self.__prefs_dict is None:
            self.__prefs_dict = self.__get_prefs()
        return self.__prefs_dict

    @property
    def cfg_minimal(self):
        '''
        Returns-->str: only valid, non-comment non-undef lines
        '''
        l = []
        for nt in self.cfg_nt_list:
            if nt.lt == self.LINE_SET_KV or nt.lt == self.LINE_UNDEF_COMMENT:
                l.append(nt.raw)
        ret = '\n'.join(l)
        if ret and not ret.endswith('\n'):
            ret += '\n'
        return ret

    @property
    def cfg_raw(self):
        '''Returns-->str'''
        ret = []
        for nt in self.cfg_nt_list:
            ret.append(nt.raw)
        ret = '\n'.join(ret)
        if ret and not ret.endswith('\n'):
            ret += '\n'
        return ret

    def __line_list_2_nt_list(self, lines):
        '''
        lines-->list of str: lines
        Returns-->list of LineNT namedtuples
        '''
        ret = []
        for (num, l) in enumerate(lines):
            match_order = [
                self.BLANK_LINE_PAT,
                self.UNDEF_LINE_PAT,
                self.COMMENT_LINE_PAT,
                self.SET_LINE_PAT,
            ]

            raw = l.rstrip('\n')
            stripped = raw.strip()
            matched = False
            valid = False
            k = None
            v = None

            for pat in match_order:
                m = re.match(pat, l)
                if m:
                    matched = True
                else:
                    continue
                if pat == self.BLANK_LINE_PAT:
                    lt = self.LINE_EMPTY
                    break
                elif pat == self.UNDEF_LINE_PAT:
                    k = m.groupdict()['CFG_KEY']
                    if k.startswith(self.__config):
                        k = k[7:]
                    v = None
                    valid = True
                    lt = self.LINE_UNDEF_COMMENT
                    break
                elif pat == self.COMMENT_LINE_PAT:
                    lt = self.LINE_COMMENT
                    break
                elif pat == self.SET_LINE_PAT:
                    k = m.groupdict()['CFG_KEY']
                    if k.startswith(self.__config):
                        k = k[7:]
                    v = m.groupdict()['CFG_VAL']
                    valid = True
                    lt = self.LINE_SET_KV
                    break
            if not matched:     # invalid (uncommented) non-blank line
                self.debug('(%d) Invalid line: %s' % (num, stripped))
                lt = self.LINE_INVALID

            ret.append(
                LineNT(
                    num=num, raw=raw, stripped=stripped,
                    matched=matched, valid=valid,
                    lt=lt, k=k, v=v,
                )
            )

        return ret

    def __nt_list_2_dict(self, ntl, undef=True):
        '''
        ntl-->list of LineNT: as returned by line_list_2_nt_list
        undef-->bool: If True, comented lines representing 'undef' are also returned
        Returns-->OrderedDict
            undef values have value = None
        '''
        ret = OrderedDict()
        ignore = [self.LINE_EMPTY, self.LINE_INVALID, self.LINE_COMMENT]
        if not undef:
            ignore.append(self.LINE_UNDEF_COMMENT)
        ignore = dict.fromkeys(ignore)

        for nt in ntl:
            if nt.lt in ignore:
                continue
            (k, v) = (nt.k, nt.v)
            if k.startswith(self.__config):
                k = k[len(self.__config):]
            ret[k] = v
        return ret

    def __get_prefs(self):
        '''
        Processes each file in self.prefs_list
        Returns-->OrderedDict
        '''
        ret = OrderedDict()

        for f in self.prefs_list:
            try:
                (contents, _) = file_contents(f, debug=self.__debug_fd)
            except Exception as e:
                print(format_exc(e))
                continue

            lines = contents.splitlines()
            ntl = self.__line_list_2_nt_list(lines)
            d = self.__nt_list_2_dict(ntl=ntl, undef=False)

            for (k, v) in d.items():
                ret[k] = v

        return ret

    def compare(self):
        '''
        Compares self.prefs_dict with dict derived from self.cfg
        Returns-->OrderedDict:
            key-->str: CONFIG_KEY without leading self.__prefix
            value-->(src-->str, dest-->str):
                src-->str: value of key in self.prefs_dict
                dest-->str: value of key in self.cfg_dict (or None)
        '''
        ret = OrderedDict()
        p = self.prefs_dict
        c = self.cfg_dict
        for (k, v1) in p.items():
            if k not in c:
                ret[k] = (v1, None)
                continue
            v2 = c[k]
            if v1 == v2:
                continue
            ret[k] = (v1, v2)
        return ret

    def __invalidate_cfg_vars(self):
        self.__fstr = None
        self.__line_list = None
        self.__nt_list = None
        self.__cfg_dict = None

    def write_cfg(self):
        '''
        (Over)writes cfg from self.__nt_list, updating with prefs_dict
        Returns-->bool: success
        '''
        try:
            to_change = self.compare()
            out_lines = []
            unchanged = dict.fromkeys([self.LINE_EMPTY, self.LINE_COMMENT])
            if self.prefs_dict:
                for nt in self.cfg_nt_list:
                    if nt.lt == self.LINE_INVALID:
                        continue   # ignore invalid lines
                    if nt.lt in unchanged:
                        out_lines.append(nt.raw)
                        continue
                    # LINE_SET_KV or LINE_UNDEF_COMMENT
                    (k, v) = (nt.k, nt.v)
                    if k in to_change:
                        v = to_change[k][0]
                        print('    %s=%s' % (k, v))
                        del to_change[k]
                    out_lines.append('%s%s=%s' % (self.__config, k, v))

                # Now write what remains in to_change (completely missing in cfg)
                for (k, (v1, v2)) in to_change.items():
                    out_lines.append('%s%s=%s' % (self.__config, k, v1))

            with open(self.cfg, mode='w', encoding=self.encoding) as f:
                for l in out_lines:
                    f.write(l + '\n')
                f.flush()
                f.close()
            self.__invalidate_cfg_vars()
            return True
        except Exception as e:
            print(format_exc(e))
            return False

    def show_comparison(self, d, pre=True, kd=None):
        '''
        d-->OrderedDict: as returned by compare()
            key-->str: CONFIG_KEY without leading self.__prefix
            value-->(src-->str, dest-->str):
                src-->str: value of key in self.prefs_dict
                dest-->str: value of key in self.cfg_dict (or None)
        pre-->bool:
            if True will just display what is GOING to be set
            else will show what was NOT set successfully
        '''
        if not d:
            print('All kernel config prefs have been set')
            return
        if pre:
            print('Setting following kernel config prefs:')
            for (k, (v1, v2)) in d.items():
                print('    %s=%s   (cfg %s)' % (k, v1, str(v2)))
        else:
            for (k, (v1, v2)) in list(d.items()):
                if kd and k in kd and len(kd[k]) == 1:
                    nt = kd[k][0]
                    if v2 is None and v1 == nt.default:
                        v2 = nt.default
                        d[k] = (v1, v2)
                    elif v2 is None and nt.default is None:
                        v2 = 'n'
                        d[k] = (v1, v2)
                if d[k][0] == d[k][1]:
                    del d[k]

            if d:
                print('Following kernel config prefs were not set:')
                for (k, (v1, v2)) in d.items():
                    if v1 != v2:
                        print('    %s=%s   (cfg %s)' % (k, v1, str(v2)))

    def diffs(self, pre=True):
        '''
        Compares prefs_dict with cfg
        pre-->bool:
            if True will just display what is GOING to be set
            else will show what was NOT set successfully
        Returns-->True if there ARE differences; False otherwise
        '''
        d = self.compare()
        self.show_comparison(d=d, pre=pre)
        return len(d) > 0

    def new_kernel_config_dict(self):
        '''
        Returns-->OrderedDict:
            key: CFG_KEY
            val: default
        '''
        oldpwd = os.getcwd()
        os.chdir(os.path.dirname(self.cfg))

        ret = OrderedDict()
        cmd = 'make -s listnewconfig 2>/dev/null'
        out = subprocess.check_output(cmd, shell=True).decode(DEFAULT_ENCODING)
        out = out.strip()

        kv_pat = re.compile('^(?P<CFG_KEY>\S+)=(?P<CFG_VAL>.*?)$')
        for l in out.splitlines():
            l = l[7:]
            m = re.match(kv_pat, l)
            if m:
                try:
                    k = m.groupdict()['CFG_KEY']
                    v = m.groupdict()['CFG_VAL']
                    ret[k] = v
                except:
                    pass

        os.chdir(oldpwd)
        return ret

    def set_new_kernel_config_vals(self, d, kd):
        '''
        d-->OrderedDict: as returned by new_kernel_config_dict()
            key-->CGF_VAL
            val-->CFG_VAL
        kd-->OrderedDict as returned by KernelConfigVars.kconfig_2_nt_dict
            key-->str: CFG_KEY
            val-->list of CfgVarNT
        Returns-->bool: success
        '''

        oldpwd = os.getcwd()
        os.chdir(os.path.dirname(self.cfg))

        if not d:
            return True

        print('Adding symbols for new kernel')
        ret = False
        num_tristate = 0
        try:
            with open(self.cfg, mode='a+', encoding=self.encoding) as cfg:
                for (k, v) in d.items():
                    if k in kd:
                        for v1 in kd[k]:
                            if v1.t == 'tristate':
                                v = 'm'
                                num_tristate += 1
                    if not k.startswith(self.__config):
                        k = self.__config + k
                    cfg.write('%s=%s\n' % (k, v))
                cfg.flush()
                cfg.close()
                self.__invalidate_cfg_vars()
                if d:
                    print('%-35s : %d' % ('New kernel symbols added', len(d),))
                if num_tristate > 0:
                    print('%-35s : %d' % ('Tristate symbols set to m', num_tristate,))
                ret = True
        except Exception as e:
            print(format_exc(e))
            pass

        os.chdir(oldpwd)
        return ret

    def qns_for_new_kernel(self, cmd=None, cmd_out_file=None, chosen_out_file=None):
        '''
        cmd-->str: command + args to execute (after updating cfg, before re-check)
        cmd_out_file-->str: file path for output of cmd
        chosen_out_file-->str: file path for  output of answer_questions
        Returns-->bool: success
        '''
        oldpwd = os.getcwd()
        os.chdir(os.path.dirname(self.cfg))

        ret = answer_questions(
            cmd=cmd,
            out_file=cmd_out_file,
            chosen_out_file=chosen_out_file
        )
        self.__invalidate_cfg_vars()
        os.chdir(oldpwd)
        return ret

    def update_config(
        self, cmd=None, cmd_out_file=None, chosen_out_file=None
    ):
        '''
        Updates self.cfg in place, line-by-line from self.prefs_dict
        cmd-->str: command + args to execute (after updating cfg, before re-check)
        cmd_out_file-->str: file path for output of cmd
        chosen_out_file-->str: file path for  output of answer_questions

        Returns-->bool: success

        New logic - minimize calls to qns_for_new_kernel ('make oldconfig'):

            - Update from prefs_dict (if required)
            - Call qns_for_new_kernel if required (use have_new_kernel_config_vals)
            - Check diffs
        '''
        update_required = False
        if self.prefs_dict:
            if self.diffs(pre=True):
                update_required = True
        else:
            print('No prefs to set')

        if update_required:
            if not self.write_cfg():
                return False

        new_d = self.new_kernel_config_dict()
        if new_d:
            k1 = KernelConfigVars(kcu=self, syms=list(new_d.keys()))
            kd = k1.kconfig_2_nt_dict(summarize=False, details=False)
            self.set_new_kernel_config_vals(d=new_d, kd=kd)

            print('Running %s' % (cmd,))
            ret = self.qns_for_new_kernel(
                cmd=cmd,
                cmd_out_file=cmd_out_file,
                chosen_out_file=chosen_out_file
            )
            if not ret:
                print('qns_for_new_kernel failed')
                return ret
        else:
            print('No new kernel symbols')

        d = self.compare()
        k1 = KernelConfigVars(kcu=self, syms=list(self.prefs_dict.keys()))
        print('')
        kd = k1.kconfig_2_nt_dict(summarize=True, details=False)
        print('')
        self.show_comparison(d=d, pre=False, kd=kd)
        if not d:
            return True

    def __invalidate_prefs_dict(self):
        self.__prefs_dict = None


if __name__ == '__main__':
    BUILD_DIR = sys.argv[1]
    SILENT_OUT_FILE = sys.argv[2]
    CHOSEN_OUT_FILE = sys.argv[3]
    CMD_AND_ARGS = sys.argv[4]
    PREFS_FILE = sys.argv[5]

    if not os.path.isdir(BUILD_DIR):
        print('Not a directory: %s' % (BUILD_DIR,))
        exit(1)
    KERNEL_CONFIG = os.path.join(BUILD_DIR, '.config')
    if not os.path.exists(KERNEL_CONFIG):
        print('.config not found: %s' % (KERNEL_CONFIG,))
        exit(1)
    SCRIPTS_CONFIG = os.path.join(BUILD_DIR, 'scripts/config')
    if not os.path.exists(SCRIPTS_CONFIG):
        print('scripts/config does not exist: %s' % (SCRIPTS_CONFIG,))
        exit(1)

    print('Using kernel config prefs from: %s' % (PREFS_FILE,))
    print('Using kernel build dir: %s' % (BUILD_DIR,))
    print('Using kernel config make command: %s' % (CMD_AND_ARGS,))
    print('Kernel config make output in %s' % (SILENT_OUT_FILE,))
    print('Kernel config make choices made in %s' % (CHOSEN_OUT_FILE,))

    # IMPORTANT - move to Linux kernel source dir
    os.chdir(BUILD_DIR)

    '''
    prefs_list = ['/home/sundar/git/kernel_build/config/config.prefs']
    cfg = '/home/sundar/rdp/__kernel_build/build/linux/.config'
    cmd = 'make oldconfig'
    cmd_out_file = '/tmp/oldconfig.out'
    chosen_out_file = '/tmp/chosen.out'
    '''

    cfg = os.path.join(BUILD_DIR, '.config')
    prefs_list = [PREFS_FILE]
    cmd = CMD_AND_ARGS
    cmd_out_file = SILENT_OUT_FILE
    chosen_out_file = CHOSEN_OUT_FILE

    kcu = KernelConfigUpdater(
        cfg=cfg, prefs_list=prefs_list,
    )

    kcu.update_config(
        cmd=cmd,
        cmd_out_file=cmd_out_file,
        chosen_out_file=chosen_out_file,
    )
