#!/usr/bin/env python3

import sys
import os
from collections import OrderedDict
import re
import pexpect
import time
from collections import namedtuple
import subprocess
from textwrap import wrap
from pyutils import (
    DEFAULT_ENCODING,
    format_exc,
    file_contents,
    remove_blank_lines,
    FileWriteSingleton,
)


# Do not change this unless kernel .config format changes!
_CONFIG = 'CONFIG_'

CMD_LISTNEWCONFIG = 'make -s listnewconfig 2>/dev/null'
CMD_OLDCONFIG = 'make -s oldconfig'
CMD_ARG_MAX = 'getconf ARG_MAX'

CMD_LEN_THRESHOLD = 4096
CMD_LEN_SAFETY_FACTOR = 200
ANSWER_QUESTIONS_TIMEOUT = 5
MAX_ATTEMPTS = 3

GD_KEY = 'CFG_KEY'
GD_VAL = 'CFG_VAL'
GD_TYPE = 'TYPE'
GD_PROMPT = 'PROMPT'
GD_DEFAULT = 'DEFAULT'
GD_QUOTED = 'QUOTED'

KV_PAT = re.compile('^(?P<%s>\S+)\s*=\s*(?P<%s>.*?)$' % (
    GD_KEY, GD_VAL
))
BLANK_LINE_PAT = re.compile('^\s*$')
COMMENT_LINE_PAT = re.compile('^\s*#')
UNINDENTED_LINE_PAT = re.compile('^\S+')

# LineNT lt values
LINE_INVALID = 0
LINE_EMPTY = 1
LINE_UNDEF_COMMENT = 2
LINE_COMMENT = 3
LINE_SET_KV = 4

# KConfig Problem types:
KCONFIG_OK = 0
KCONFIG_NOT_FOUND = 1
KCONFIG_MULTI_DEFS = 2
KCONFIG_NO_TYPE = 4
KCONFIG_NO_DEFAULT = 8
KCONFIG_DEFAULT_DIFFERENT = 16
KCONFIG_VALUE_DIFFERENT = 32

DEBUG_SINGLETON = None
BUILD_DIR = None
CMD_OUT_FILE = None


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
        'lt', 'k', 'v', 'f'
    ]
)


class ChosenOutSingleton(FileWriteSingleton):
    pass


def debug(s):
    '''
    s-->str
    Outputs to DEBUG_SINGLETON (if set)
    '''
    if DEBUG_SINGLETON:
        try:
            DEBUG_SINGLETON.write(s)
        except:
            pass


class CfgParser(object):
    '''
    Parses a single config.prefs or Linux kernel .config file
    Exposes:
        contents-->str
        lines-->list of str
        ntl-->list of LineNT namedtuple
        prefs_dict-->OrderedDict
    '''
    UNDEF_LINE_PAT = re.compile(
        '^\s*#\s*(?P<%s>\S+)\s+is not set$' % (GD_KEY,))
    SET_LINE_PAT = re.compile(
        '^(?P<%s>\S+)\s*=\s*(?P<%s>\S+.*?)$' % (GD_KEY, GD_VAL))

    def __init__(self, f, undef=False):
        '''
        f-->str: path to input file
        undef-->bool: If True, commented lines representing 'undef' are also parsed
        '''
        self.f = f
        self.undef = undef
        self.contents = self.__contents()

        self.lines = self.contents.splitlines()
        self.ntl = self.__line_list_2_nt_list(self.lines, f=self.f)
        self.ntd = self.__nt_list_2_ntl_dict(self.ntl)
        self.prefs_dict = self.__nt_dict_2_dict(ntd=self.ntd)

    def __contents(self):
        '''Returns-->str'''
        try:
            (contents, _) = file_contents(self.f, debug=DEBUG_SINGLETON)
            if not contents.endswith('\n'):
                contents += '\n'
            return contents
        except Exception as e:
            debug(format_exc(e))
            return ''

    def __nt_dict_2_dict(self, ntd):
        '''
        ntd-->OrderedDict: as returned by __nt_list_2_ntl_dict
        Returns-->OrderedDict
            undef values have value = None
        '''
        ret = OrderedDict()
        for (k, nt) in ntd.items():
            ret[k] = nt.v
        return ret

    def __nt_list_2_ntl_dict(self, ntl):
        '''
        ntl-->list of LineNT namedtuples
        Returns-->OrderedDict:
            key-->nt.k
            value-->LineNT namedtuple
        '''
        ret = OrderedDict()

        ignore = [LINE_EMPTY, LINE_INVALID, LINE_COMMENT]
        if not self.undef:
            ignore.append(LINE_UNDEF_COMMENT)
        for nt in ntl:
            if nt.lt in ignore:
                continue
            ret[nt.k] = nt
        return ret

    def __line_list_2_nt_list(self, lines, f=None):
        '''
        lines-->list of str: lines
        f-->str: file path or None
        Returns-->list of LineNT namedtuples
        '''
        ret = []
        for (num, l) in enumerate(lines):
            match_order = [
                BLANK_LINE_PAT,
                self.UNDEF_LINE_PAT,
                COMMENT_LINE_PAT,
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
                if pat == BLANK_LINE_PAT:
                    lt = LINE_EMPTY
                    break
                elif pat == self.UNDEF_LINE_PAT:
                    k = m.groupdict()['CFG_KEY']
                    if k.startswith(_CONFIG):
                        k = k[len(_CONFIG):]
                    v = None
                    valid = True
                    lt = LINE_UNDEF_COMMENT
                    break
                elif pat == COMMENT_LINE_PAT:
                    lt = LINE_COMMENT
                    break
                elif pat == self.SET_LINE_PAT:
                    k = m.groupdict()['CFG_KEY']
                    if k.startswith(_CONFIG):
                        k = k[len(_CONFIG):]
                    v = m.groupdict()['CFG_VAL']
                    valid = True
                    lt = LINE_SET_KV
                    break
            if not matched:     # invalid (uncommented) non-blank line
                debug('(%d) Invalid line: %s' % (num, stripped))
                lt = LINE_INVALID

            ret.append(
                LineNT(
                    num=num, raw=raw, stripped=stripped,
                    matched=matched, valid=valid,
                    lt=lt, k=k, v=v, f=f,
                )
            )
        return ret


class Prefs(object):
    '''
    Reads a list of config.prefs files
    '''
    def __init__(self, prefs_list=[]):
        self.prefs_list = prefs_list
        self.prefs_dict = self.__get_prefs()

    def __get_prefs(self):
        '''
        Processes each file in self.prefs_list
        Returns-->OrderedDict
        '''
        ret = OrderedDict()
        for f in self.prefs_list:
            try:
                parser = CfgParser(f=f, undef=False)
                if not parser.contents:
                    continue
                d = parser.prefs_dict
                ntd = parser.ntd
                for (k, v) in d.items():
                    if k in ret and ret[k] != v:
                        msg = 'Redefinition of %s in %s old(%s) new(%s)' % (
                            k, f, str(ret[k]), str(v),
                        )
                        debug(msg)
                        if k in ntd:
                            msg = '%s previously defined in %s (%d)' % (
                                k, ntd[k].f, ntd[k].num
                            )
                            debug(msg)
                    ret[k] = v
            except Exception as e:
                debug(format_exc(e, msg='CfgParser(%s)' % (f,)))
                continue

        return ret


class LinuxDotConfig(object):
    '''
    Read a Linux kernel .config file
    Update a Linux kernel .config from a dict
    '''
    UNDEF_LINE_PAT = '^\s*#\s*(?P<CFG_KEY>\S+)\s+is not set$'
    SET_LINE_PAT = '^(?P<CFG_KEY>\S+)\s*=\s*(?P<CFG_VAL>\S+.*?)$'

    def __init__(self):
        self.encoding = 'ascii'
        self.init()

    def init(self):
        '''
        Sets instance vars
        '''
        self.config = os.path.join(BUILD_DIR, '.config')
        f = os.path.join(BUILD_DIR, '.config')
        try:
            parser = CfgParser(f=f, undef=True)
        except Exception as e:
            debug(format_exc(e, msg='CfgParser(%s)' % (f,)))
            raise

        self.contents = parser.contents
        self.lines = parser.lines
        self.ntl = parser.ntl
        self.prefs_dict = parser.prefs_dict

    def compare(self, d):
        '''
        d-->OrderedDict
        Compares d with .config
        Returns-->OrderedDict: kv pairs deviating from d
            key-->str: CFG_KEY without leading _CONFIG
            value-->(src-->str, dest-->str):
                src-->str: value of key in d
                dest-->str: value of key in .config (or None)
        '''
        ret = OrderedDict()
        c = self.prefs_dict
        for (k, v1) in d.items():
            if k not in c:
                ret[k] = (v1, None)
                continue
            v2 = c[k]
            if v1 == v2:
                continue
            ret[k] = (v1, v2)
        return ret

    def update(self, d, silent=False):
        '''
        d-->OrderedDict
        silent-->bool: If True, does not produce any output
        (Over)writes cfg updating / adding key-value pairs from d
        Returns-->bool: success
        '''
        try:
            to_change = self.compare(d=d)
            out_lines = []
            unchanged = dict.fromkeys([LINE_EMPTY, LINE_COMMENT])
            if not to_change:
                if not silent:
                    print('All your config prefs are already set')
                return True

            if not silent:
                print('Setting following kernel prefs:')
            if self.prefs_dict:
                for nt in self.ntl:
                    if nt.lt == LINE_INVALID:
                        continue   # ignore invalid lines
                    if nt.lt in unchanged:
                        out_lines.append(nt.raw)
                        continue
                    # LINE_SET_KV or LINE_UNDEF_COMMENT
                    (k, v) = (nt.k, nt.v)
                    if k in to_change:
                        v = to_change[k][0]
                        if not silent:
                            print('    %s=%s' % (k, v))
                        del to_change[k]
                    out_lines.append('%s%s=%s' % (_CONFIG, k, v))

                # Now write what remains in to_change (completely missing in cfg)
                for (k, (v1, v2)) in to_change.items():
                    if not silent:
                        print('    %s=%s' % (k, v1))
                    out_lines.append('%s%s=%s' % (_CONFIG, k, v1))

            with open(self.config, mode='w', encoding=self.encoding) as f:
                for l in out_lines:
                    f.write(l + '\n')
                f.flush()
                f.close()
                self.init()   # re-read
            return True
        except Exception as e:
            print(format_exc(e))
            return False


class KConfigsReader(object):
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

    def __init__(self, syms=[]):
        '''
        syms-->list of str: CFG_KEYS. If syms is empty, ALL CFG_KEYs are considered
        '''
        start_time = time.time()

        self.syms = syms
        (self.ntd, n) = self.get_nt_dict()

        debug('Analyzed %d Kconfig files in %.1f secs' % (
            n, time.time() - start_time,
        ))

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
        if len(ret) > CMD_LEN_THRESHOLD:
            max_cmd_len = subprocess.check_output(CMD_ARG_MAX, shell=True)
            max_cmd_len = int(max_cmd_len.decode(DEFAULT_ENCODING))
            if len(ret) < (max_cmd_len - CMD_LEN_SAFETY_FACTOR):
                ret = []
                l2 = ['\S+']
                for i in l1:
                    for j in l2:
                        ret.append('^%s %s$' % (i, j))
                ret = '|'.join(ret)
        return ret

    def __kconfig_files(self):
        '''
        Returns-->list of str: Kconfig file paths UNDER BUILD_DIR
        Only those Kconfig files that contain '^config \S+ | ^menuconfig \S+'
        are returned - not all. There are ~24 Kconfig files without this pattern
        (ver 5.9-rc6) and none of them are relevant (checked manually)

        If length of self.syms is large enough, concatenating them into a grep pattern
        will make the command line too long. In that case (checked with 'getconf ARG_MAX'
        this function will return ALL Kconfig files that define at least one symbol
        and filtering will (should) happen in file_2_nt_dict
        '''
        oldpwd = os.getcwd()
        os.chdir(BUILD_DIR)

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
        UNINDENTED_LINE_PAT = re.compile('^\S+')

        acc = []
        for l in lines:
            if re.match(UNINDENTED_LINE_PAT, l):
                # Little hack when type def or default line is not indented
                # but has no blank line above
                if acc and re.match(BLANK_LINE_PAT, acc[-1]):
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
        os.chdir(BUILD_DIR)

        key_pat = re.compile(
            '^(config|menuconfig)\s+(?P<%s>\S+)' % (GD_KEY,),
            re.MULTILINE + re.DOTALL
        )
        type_prompt_pat = re.compile(
            '^\s+(?P<%s>bool|tristate|string|hex|int)\s*?(?P<%s>.*?)$' % (
                GD_TYPE, GD_PROMPT,
            ),
            re.MULTILINE,
        )
        unquote_pat = re.compile('^"(?P<%s>.*?)"$' % (GD_QUOTED,))
        default_pat = re.compile(
            '^\s+(default|def_bool|def_tristate)\s+(?P<%s>.*$)$' % (
                GD_DEFAULT,
            ),
            re.MULTILINE,
        )
        type_default_pat = re.compile(
            '^\s+def_(?P<%s>bool|tristate)\s+(?P<%s>.*$)$' % (
                GD_TYPE, GD_DEFAULT
            ),
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
                k = m.groupdict()[GD_KEY]
            except Exception as e:
                continue
            if self.syms and k not in syms:
                continue
            m = re.search(type_prompt_pat, sec)
            if m:
                try:
                    t = m.groupdict()[GD_TYPE]
                except:
                    pass
                try:
                    p = m.groupdict()[GD_PROMPT]
                    m = re.search(unquote_pat, p)
                    if m:
                        try:
                            p = m.groupdict()[GD_QUOTED]
                        except:
                            pass
                except:
                    pass
            m = re.search(default_pat, sec)
            if m:
                try:
                    default_str = m.groupdict()[GD_DEFAULT]
                    m = re.search(unquote_pat, default_str)
                    if m:
                        try:
                            default_str = m.groupdict()[GD_QUOTED]
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
                        t = m.groupdict()[GD_TYPE]
                    except:
                        pass
                    if not default_str:
                        try:
                            default_str = m.groupdict()[GD_DEFAULT]
                            m = re.search(unquote_pat, default_str)
                            if m:
                                try:
                                    default_str = m.groupdict()[GD_QUOTED]
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

    def get_nt_dict(self):
        '''
        Returns-->(d, n):
            d-->OrderedDict:
                key-->str: CFG_KEY
                val-->list of CfgVarNT
            n-->int: number of Kconfig files considered
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

        return (ret, len(kconfig_files))

    def get_type(self, k):
        '''
        k-->str: CFG_KEY
        Returns-->str or None
        '''
        ret = None
        if k not in self.ntd:
            return ret
        ntl = self.ntd[k]
        if len(ntl) == 1:
            return ntl[0].t
        for nt in ntl:
            if nt.t is not None:
                return nt.t
        return ret

    def get_default(self, k):
        '''
        k-->str: CFG_KEY
        Returns-->str or None
        '''
        ret = None
        if k not in self.ntd:
            return ret
        ntl = self.ntd[k]
        if len(ntl) == 1:
            return ntl[0].default
        for nt in ntl:
            if nt.default is not None:
                return nt.default
        return ret


class Comparisons(object):
    @classmethod
    def check_prefs(self, a, b, kcr):
        '''
        a-->OrderedDict:
            key-->str: CFG_KEY
            val-->str: CFG_VAL or None
        b-->OrderedDict: may be LinuxDotConfig.prefs_dict
            key-->str: CFG_KEY
            val-->str: CFG_VAL or None
        kcr-->KConfigsReader object
        Returns-->OrderedDict:
            key-->str: CFG_KEY in a
            val-->(v1, v2, prob):
                v1-->str: val in d
                v2-->str or None: val in b or self.get_default(k)
                prob-->int: bits set with KCONFIG_*

            # KConfig Problem types:
            KCONFIG_OK = 0 - not used
            KCONFIG_NOT_FOUND = 1
            KCONFIG_MULTI_DEFS = 2
            KCONFIG_NO_TYPE = 4
            KCONFIG_NO_DEFAULT = 8
            KCONFIG_DEFAULT_DIFFERENT = 16
            KCONFIG_VALUE_DIFFERENT = 32
        '''
        ret = OrderedDict()

        ntd = kcr.ntd

        for (k, v1) in a.items():
            prob = KCONFIG_OK
            if k in b and b[k] == v1:
                continue

            if k in b and b[k] is not None:
                prob += KCONFIG_VALUE_DIFFERENT
                ret[k] = (v1, b[k], prob)
                continue

            # k not in b

            if k not in ntd:
                v2 = None
                prob += KCONFIG_NOT_FOUND
            else:
                ntl = ntd[k]
                if len(ntl) > 1:
                    prob += KCONFIG_MULTI_DEFS
                t = kcr.get_type(k)
                if t is None:
                    prob += KCONFIG_NO_TYPE
                default = kcr.get_default(k)
                v2 = default
                if default is None:
                    prob += KCONFIG_NO_DEFAULT
                if v2 == v1:
                    continue
                prob += KCONFIG_VALUE_DIFFERENT

                ret[k] = (v1, v2, prob)
                continue

        return ret

    @classmethod
    def describe_changes(
        cls, d, src, dest, kcr=None, counts=0, details=0,
        summary=True, showdefs=True, showsecs=True,
    ):
        '''
        d-->OrderedDict: areturned by Comparisons.check_prefs
            key-->str: CFG_KEY in a
            val-->(v1, v2, prob):
                v1-->str: val in d
                v2-->str or None: val in b or self.get_default(k)
                prob-->int: bits set with KCONFIG_*

            # KConfig Problem types:
            KCONFIG_OK = 0 - not used
            KCONFIG_NOT_FOUND = 1
            KCONFIG_MULTI_DEFS = 2
            KCONFIG_NO_TYPE = 4
            KCONFIG_NO_DEFAULT = 8
            KCONFIG_DEFAULT_DIFFERENT = 16
            KCONFIG_VALUE_DIFFERENT = 32
        src-->str
        dest-->str
        kcr-->KConfigsReader object
        counts-->int: if non-zero show counts only for (prob & showonly) != 0
            i.e. showonly is an AND of KCONFIG_* bits
        details-->int: if non-zero show details only for (prob & showonly) != 0
            i.e. showonly is an AND of KCONFIG_* bits
        summary-->bool: show confirmation even if d is empty
        showdefs-->bool: If True, show Kconfig files for keys with KCONFIG_MULTI_DEFS
        showsecs-->bool: If True, show Kconfig SECTIONS for keys with KCONFIG_MULTI_DEFS
        '''
        def indent(s, n=1):
            if not s:
                return s
            left = '    '
            s = remove_blank_lines(s)
            return (left * n) + ('\n' + (left * n)).join(s.splitlines())

        def wrap_indent(s, n=1):
            if not s:
                return s
            s = '\n'.join(wrap(
                s,
                width=70,
                initial_indent='',
                subsequent_indent=''
            ))
            return indent(s=s, n=n)

        if not d and summary:
            print('All symbols in %s unchanged in %s' % (src, dest))
            return

        src_dest_fmt = '%s --> %s' % (src, dest)

        counts_map = OrderedDict()
        counts_map[KCONFIG_VALUE_DIFFERENT] = 'changed'
        counts_map[KCONFIG_NOT_FOUND] = 'missing'
        counts_map[KCONFIG_MULTI_DEFS] = 'multiple definitions'
        counts_map[KCONFIG_NO_TYPE] = 'no type definition'
        counts_map[KCONFIG_NO_DEFAULT] = 'no default'
        counts_map[KCONFIG_DEFAULT_DIFFERENT] = 'default different'

        counts_num = OrderedDict.fromkeys(counts_map.keys(), 0)
        counts_out = OrderedDict.fromkeys(counts_map.keys())
        table_out = OrderedDict.fromkeys(counts_map.keys())
        details_out = OrderedDict.fromkeys(counts_map.keys())
        syms_out = OrderedDict.fromkeys(counts_map.keys(), [])

        for (k, (v1, v2, prob)) in d.items():
            for p1 in counts_map.keys():
                if (prob & p1):
                    counts_num[p1] = counts_num[p1] + 1
                    syms_out[p1].append(k)

        for p1 in counts_map.keys():
            if counts_num[p1]:
                msg_fmt = '%s %s' % (src_dest_fmt, counts_map[p1])
                msg_fmt = '%-70s : %%d' % (msg_fmt,)
                lines = []
                lines.append(msg_fmt % (counts_num[p1],))
                if (not details) or (details & prob):
                    if syms_out[p1]:
                        lines.append(indent(counts_map[p1]))
                        lines.append(wrap_indent(' '.join(syms_out[p1]), n=2))
                if len(lines) > 1:
                    counts_out[p1] = '\n'.join(lines)
                else:
                    counts_out[p1] = lines[0]

        LEGEND = OrderedDict(
            Key=None,
            SRC=None,
            DST=None,
            NS='Not set',
            VD='Value present and different',
            NF='Definition not found in Kconfigs',
            MD='Multiple definitions found in Kconfigs',
            NT='No type definition found in Kconfigs',
            ND='No default found in Kconfigs - will default to "n"',
            DD='Default in Kconfig different',
        )
        COLS = list(LEGEND.keys())
        ROW_FMT = '%-48s %-8s %-8s  ' + ('%2s ' * (len(COLS) - 3))
        TABLE_HEADER = ROW_FMT % tuple(COLS)
        BITSET = '+'
        BITUNSET = '_'
        TOO_LONG = 'TOO_LONG'
        V1_V2_LEN = 8    # Align with ROW_FMT

        for (k, (v1, v2, prob)) in d.items():
            if details and not (details & prob):
                continue

            (v1, v2) = (v1 and v1 or '', v2 and v2 or '')
            (v1, v2) = (str(v1).strip(), str(v2).strip())
            if len(v1) > V1_V2_LEN:
                v1 = TOO_LONG
            if len(v2) > V1_V2_LEN:
                v2 = TOO_LONG

            row = ROW_FMT % (
                k, v1, v2,
                (not v2) and BITSET or BITUNSET,
                (prob & KCONFIG_VALUE_DIFFERENT) and BITSET or BITUNSET,
                (prob & KCONFIG_NOT_FOUND) and BITSET or BITUNSET,
                (prob & KCONFIG_MULTI_DEFS) and BITSET or BITUNSET,
                (prob & KCONFIG_NO_TYPE) and BITSET or BITUNSET,
                (prob & KCONFIG_NO_DEFAULT) and BITSET or BITUNSET,
                (prob & KCONFIG_DEFAULT_DIFFERENT) and BITSET or BITUNSET,
            )
            table_out[k] = row
            # Can't get details without kcr
            if not kcr:
                continue
            if k not in kcr.ntd:
                continue
            if (prob & KCONFIG_MULTI_DEFS):
                lines = []
                ntl = kcr.ntd[k]
                for nt in ntl:
                    if not nt.f:
                        continue
                    lines.append(str(nt.f))
                    if not showsecs:
                        continue
                    if not nt.sec:
                        continue
                    lines.append(indent(nt.sec))
                if lines:
                    details_out[k] = '\n'.join(lines)

        # Everything calculated - now display based on flags

        # Counts
        for v in [x for x in counts_out.values() if x is not None]:
            print(v)

        # Table
        l = [x for x in table_out.values() if x is not None]
        if l:
            print(TABLE_HEADER)
            for v in l:
                print(v)

        # Definitions for symbols defined multuply (and secs if show secs)
        if showdefs:
            for (k, v) in details_out.items():
                if not v:
                    continue
                print(k)
                print(indent(v))


class OldConfig(object):
    '''
    Runs CMD (make oldconfig) if required
    Collects all data required for comparisons
    '''

    def __init__(self, prefs_list):
        '''
        prefs_list-->list of str: file paths
        '''
        # Need to call run() spearately to check return value
        self.new_syms = self.new_kernel_syms()
        prefs = Prefs(prefs_list=prefs_list)
        self.prefs_dict = prefs.prefs_dict
        self.pre_ldc = LinuxDotConfig()
        self.post_ldc = self.pre_ldc
        if self.new_syms:
            self.non_def_ans_dict = self.tristate_sym_dict(self.new_syms)
        else:
            self.non_def_ans_dict = OrderedDict()
        self.update_dict = OrderedDict()
        self.error_dict = OrderedDict()

        self.attempts = 0

    def run(self):
        '''
        Returns-->bool: success
        '''

        while self.attempts < MAX_ATTEMPTS:
            if not self.new_syms and not self.prefs_dict and not self.error_dict:
                print('No kernel prefs to update')
                return True
            if not self.update_ldc():
                return False
            if not self.new_syms:
                return True
            if not self.run_oldconfig():   # updates self.attempts, sets self.kcr
                return False

            self.error_dict = Comparisons.check_prefs(
                a=self.update_dict,
                b=self.post_ldc.prefs_dict,
                kcr=self.kcr,
            )
            self.prune_error_dict()

            if self.error_dict:
                self.show_error_dict()
            else:
                if self.new_syms:
                    print('All prefs and answer_question responses set in kernel config')
                else:
                    print('All prefs set in kernel config')
                break

        if self.error_dict:
            self.show_error_dict()
            return False
        return True

    def prune_error_dict(self):
        '''
        [A] We IGNORE errors where update_dict has 'n' and config has 'y', 'm' or None
        [B] We also IGNORE errors where config value is not in ['y', 'n', 'm']
            because we USUALLY do not set such values
        Such differences are ignored ONLY when the symbol is not in prefs_dict
        All keys in prefs_dict are never ignored until MAX_ATTEMPTS is exceeded
        '''
        for (k, (v1, v2, prob)) in list(self.error_dict.items()):
            if k in self.prefs_dict:
                continue
            if v2 not in ['y', 'n', 'm']:
                try:
                    del self.error_dict[k]
                except:
                    pass
            if v1 != 'n':
                continue
            if v2 in [None, 'y', 'm']:
                try:
                    del self.error_dict[k]
                except:
                    pass

    def update_ldc(self):
        '''
        Returns-->bool: success
        '''

        if not self.new_syms and not self.prefs_dict and not self.error_dict:
            print('No kernel prefs to update')
            return True

        u = OrderedDict()
        if self.error_dict:
            for (k, (v1, v2, prob)) in self.error_dict.items():
                u[k] = v1
            print('Trying again to set your prefs and answer_question responses')
            success = self.post_ldc.update(u, silent=True)
            if not success:
                return success
            self.update_dict = u
            return success

        # First run
        if self.prefs_dict:
            success = self.post_ldc.update(self.prefs_dict, silent=False)
            if not success:
                return success
        if self.new_syms:
            success = self.post_ldc.update(self.new_syms, silent=True)
            if not success:
                return success
        u.update(self.prefs_dict)
        u.update(self.new_syms)
        self.update_dict = u
        return success

    def run_oldconfig(self):
        '''
        Returns-->bool: success
        '''
        self.attempts += 1
        print('Running make oldconfig - attempt(%d)' % (self.attempts))
        start_time = time.time()
        (success, self.non_def_ans_dict) = self.answer_questions()
        if not success:
            print('%s failed' % (CMD_OLDCONFIG,))
            return success
        print('Oldconfig completed (%.1f seconds)' % (
            time.time() - start_time
        ))
        self.post_ldc = LinuxDotConfig()
        if not getattr(self, 'kcr', None):
            self.kcr = KConfigsReader()
        return True

    def show_error_dict(self):
        '''Returns-->None'''
        if not self.error_dict:
            return

        TOO_LONG = 'TOO_LONG'
        FMT = '    %-52s  %-8s  %-8s'
        V1_V2_LEN = 8    # Align with FMT

        print('Some of your prefs or answer_question responses not set')
        print('Total: %d' % (len(self.error_dict),))
        for (k, (v1, v2, prob)) in self.error_dict.items():
            (v1, v2) = (v1 and v1 or '', v2 and v2 or '')
            (v1, v2) = (str(v1).strip(), str(v2).strip())
            if len(v1) > V1_V2_LEN:
                v1 = TOO_LONG
            if len(v2) > V1_V2_LEN:
                v2 = TOO_LONG
            print(FMT % (k, v1, v2))

    def tristate_sym_dict(self, d):
        '''
        d-->OrderedDict: as returned by new_kernel_syms
            key-->CFG_KEY
            val-->CFG_VAL
        Returns-->OrderedDict:
            key-->CFG_KEY
            val-->"m"
        '''
        if not getattr(self, 'kcr', None):
            self.kcr = KConfigsReader()
        kcr = self.kcr

        ret = OrderedDict()
        for (k, v) in d.items():
            t = kcr.get_type(k)
            if t == 'tristate':
                ret[k] = 'm'
        return ret

    def answer_questions(self):
        '''
        Returns-->(success, d):
            success-->bool
            d-->OrderedDict: Non default answers chosen
                key-->str: CFG_KEY
                val-->str: chosen
        '''
        start_time = time.time()
        c = pexpect.spawn(
            CMD_OLDCONFIG,
            encoding=DEFAULT_ENCODING,
            timeout=ANSWER_QUESTIONS_TIMEOUT
        )
        # print('Child process PID = %d' % (c.pid,))
        c.logfile = open(CMD_OUT_FILE, 'a+')

        pat_desc = '(?P<DESC>.*?)'
        pat_key = '\((?P<%s>\S+)\)' % (GD_KEY,)
        pat_opts = '\[(?P<OPTS>\S+)]'
        pat_new = '\(NEW\)'
        pat = '^%s %s %s %s' % (pat_desc, pat_key, pat_opts, pat_new)

        question_patterns = [
            pexpect.EOF,
            pexpect.TIMEOUT,
            pat,
            '^\s*choice.*$',
        ]

        non_def_ans_dict = OrderedDict()

        debug('')
        debug('Starting answer_questions')
        while not c.eof():
            ind = c.expect(question_patterns, timeout=ANSWER_QUESTIONS_TIMEOUT)
            if ind == 0:      # EOF
                break
            elif ind == 1:      # TIMEOUT
                c.sendline('')
                continue
            elif ind == 2:        # options to choose
                ans = ''
                if c.match:
                    gd = c.match.groupdict()
                    opts = gd['OPTS']

                    # Default option (only) will be in UPPER CASE
                    def_ans = [x for x in opts if x in 'YNM']
                    if def_ans:
                        def_ans = def_ans[0]
                    else:
                        def_ans = None
                    if 'm' in opts.lower():
                        ans = [x for x in opts if x in 'mM'][0]
                    else:     # Press RETURN, accept default
                        ans = ''

                    # desc = gd['DESC'].splitlines()[-1].strip('\r\n')
                    if ans != '':
                        debug_choice = '%s=%s' % (gd[GD_KEY], ans)
                        debug('    %-54s  default(%s)  opts(%s)' % (
                            debug_choice, str(def_ans), str(opts),
                        ))
                        non_def_ans_dict[gd[GD_KEY]] = ans.lower()
                    c.sendline(ans)
                else:
                    debug('Unexpected error: index == 1, but c.match is None')
            elif ind == 3:          # choice
                # debug('--- CHOICE --- %s\n' % (c.after.splitlines()[-1],))
                c.sendline('')

        debug('Completed answer_questions (%.1f seconds)' % (
            time.time() - start_time
        ))
        debug('Non-default answers: %d - attempt(%d)' % (
            len(non_def_ans_dict),
            self.attempts,
        ))
        debug('')
        print('Non-default answers: %d - attempt(%d)' % (
            len(non_def_ans_dict),
            self.attempts,
        ))

        ret = c.isalive()
        if ret is True:
            time.sleep(1)
            ret = c.isalive()
        return (True, non_def_ans_dict)

    def new_kernel_syms(self):
        '''
        Returns-->OrderedDict:
            key: CFG_KEY
            val: default
        '''
        oldpwd = os.getcwd()
        os.chdir(BUILD_DIR)

        ret = OrderedDict()
        cmd = CMD_LISTNEWCONFIG
        out = subprocess.check_output(cmd, shell=True).decode(DEFAULT_ENCODING)
        out = out.strip()

        for l in out.splitlines():
            l = l[len(_CONFIG):]
            m = re.match(KV_PAT, l)
            if m:
                try:
                    ret[m.groupdict()[GD_KEY]] = m.groupdict()[GD_VAL]
                except:
                    pass

        os.chdir(oldpwd)
        return ret


if __name__ == '__main__':
    BUILD_DIR = sys.argv[1]
    CMD_OUT_FILE = sys.argv[2]
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
    '''
    SCRIPTS_CONFIG = os.path.join(BUILD_DIR, 'scripts/config')
    if not os.path.exists(SCRIPTS_CONFIG):
        print('scripts/config does not exist: %s' % (SCRIPTS_CONFIG,))
        exit(1)
    '''

    print('Using kernel config prefs from: %s' % (PREFS_FILE,))
    print('Using kernel build dir: %s' % (BUILD_DIR,))
    print('Using kernel config make command: %s' % (CMD_OLDCONFIG,))
    print('Kernel config make output in %s' % (CMD_OUT_FILE,))
    print('Kernel config make choices made in %s' % (CHOSEN_OUT_FILE,))

    DEBUG_SINGLETON = ChosenOutSingleton(
        f=CHOSEN_OUT_FILE,
        encoding=DEFAULT_ENCODING,
        errors=sys.stderr,
        expanduser=True,
        expandvars=True
    )
    # IMPORTANT - move to Linux kernel source dir
    os.chdir(BUILD_DIR)
    oldconfig = OldConfig(prefs_list=[PREFS_FILE])
    ret = oldconfig.run()
    if not ret:
        print('Not all config prefs or answer_question responses were updated')
    exit(0)
