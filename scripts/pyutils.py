
# PY3 - not tested on Py2

import sys
import os
import re
from collections import namedtuple
import traceback
# Make chardet optional !
try:
    import chardet
except:
    pass


# ---------- For Singleton -----------------------------------------------
import functools

__singleton_instances = {}
DEFAULT_ENCODING = sys.getdefaultencoding()


# Copied from six.py
def with_metaclass(meta, *bases):
    """Create a base class with a metaclass."""
    # This requires a bit of explanation: the basic idea is to make a dummy
    # metaclass for one level of class instantiation that replaces itself with
    # the actual metaclass.
    class metaclass(type):
        def __new__(cls, name, this_bases, d):
            return meta(name, bases, d)

        @classmethod
        def __prepare__(cls, name, this_bases):
            return meta.__prepare__(name, bases)

    return type.__new__(metaclass, "temporary_class", (), {})


def get_singleton(func):
    global __singleton_instances

    @functools.wraps(func)
    def inner(cls, *args, **kwargs):
        if cls not in __singleton_instances:
            if issubclass(cls, tuple):
                o = tuple.__new__(cls)
            elif issubclass(cls, object):
                o = object.__new__(cls)
            __singleton_instances[cls] = o
            if hasattr(o, '__init__'):
                o.__init__(*args, **kwargs)
        return __singleton_instances[cls]

    return inner


class SingletonMeta(type):
    @get_singleton
    def __call__(cls, *args, **kwargs):
        pass


class Singleton(with_metaclass(SingletonMeta)):
    '''
    Subclass from Singleton to make any class a singleton
    This implementation does not avoid metaclass conflict when
    using multiple inheritance with multiple metaclasses
    '''
    def __new__(cls, *args, **kwargs):
        pass

# ---------- End of Singleton-related ------------------------------------


PathNT = namedtuple('PathNT', [
    'exists', 'isfile', 'isdir', 'islink',
    'dir_exists', 'realpath', 'realpath_dir', 'normpath'
])


def format_exc(e, msg=None, trace=True):
    '''
    e-->Exception
    msg-->str or None
    trace-->whether traceback should be included
    Returns-->str
    '''
    l = []
    if msg:
        l.append(str(msg))
    if e:
        l.append('Exception: %s : %s' % (
            str(e),
            str(e.args),
        ))
        if trace:
            l.append(traceback.format_exc())
    ret = ''
    if l:
        ret = '\n'.join(l)
        if not ret.endswith('\n'):
            ret += '\n'
    return ret


def path_2_nt(p, expanduser=True, expandvars=False):
    '''
    p-->str
    expanduser-->bool: Expand ~ and ~user constructions
    expandvars-->bool: Expand shell variables of form $var and ${var}
        Unknown variables are LEFT UNCHANGED
    Returns-->p: PathNT namedtuple

    If p exists:
        islink = True IFF p ITSELF is a symlink
        isfile = True IFF normalized, dereferenced p is a file
        isdir = True IFF normalized, dereferenced p is a file
        dir_exists = True IFF dirname(p) exists AND is a dir
        realpath = None IFF not p.exists
        realpath_dir = None IFF not p.dir_exists
    '''
    exists = False
    isfile = False
    isdir = False
    islink = False
    dir_exists = False
    realpath = None
    realpath_dir = None
    normpath = None

    try:
        exists = os.path.exists(p)
        if exists:
            p = os.path.normpath(p)
            if expanduser:
                p = expanduser(p)
            if expandvars:
                p = expandvars(p)
            isfile = os.path.isfile(p)
            isdir = os.path.isdir(p)
            islink = os.path.islink(p)
        d = os.path.dirname(p)
        if os.path.isdir(d):
            d = os.path.normpath(d)
            if expanduser:
                d = expanduser(d)
            if expandvars:
                d = expandvars(d)
        b = os.path.basename(p)
        normpath = os.path.join(d, b)
    except:
        pass
    return PathNT(
        exists=exists,
        isfile=isfile, isdir=isdir, islink=islink,
        dir_exists=dir_exists, realpath=realpath, realpath_dir=realpath_dir,
        normpath=normpath
    )


def file_contents(f, encoding=None, debug=sys.stderr.write):
    '''
    f-->str: file path
    encoding-->str: if provided, auto-detection is not done
    debug-->callable that accepts one str parameter
        Ignored if None
        Errors on calling debug(s) are ignored
    Returns-->(fstr-->str, encoding-->str)

    If encoding is set:
        First try is with encoding - no auto-detection is done
    else:
        encoding is tried using auto-detection using chardet
    If read fails:
        utf8 and latin1 are tried in order - only if respective encoding
        has not been tried

    '''
    # Read in binary mode - may fail because of file missing or perms ...
    fstr = open(f, 'rb').read()
    # Detect encoding using chardet - only if encoding is not set
    if not encoding:
        try:
            chardet_out = chardet.detect(fstr)
            encoding = chardet_out.get('encoding', None)
        except:
            # Might (also) fail because python3-chardet is not installed
            # Only AUTO-DETECTION is affected
            pass

    # Decode - using specified or auto-detected encoding
    if encoding:
        try:
            fstr = fstr.decode(encoding)
            return (fstr, encoding)
        except:
            # Might fail for following reasons:
            #   - encoding was specified and wrong (for file)
            #   - chardet module not installed
            #   - chardet.detect could not detect encoding
            #   - chardet-detected encoding was wrong (for file)
            pass

    # Try with utf-8 if not tried already
    if encoding.lower() not in ['utf-8', 'utf8']:
        encoding = 'utf-8'
        if debug:
            try:
                debug('Retrying with encoding: %s\n' % (str(encoding)))
            except:
                pass
        try:
            fstr = fstr.decode(encoding)
            return (fstr, encoding)
        except:
            pass
    # Fall back to latin1 - should always work?
    if encoding.lower() not in ['latin1']:
        encoding = 'latin1'
        if debug:
            try:
                debug('Retrying with encoding: %s\n' % (str(encoding)))
            except:
                pass
        try:
            fstr = fstr.decode(encoding)
            return (fstr, encoding)
        except:
            pass


def file_contents_basic(f):
    '''
    f-->str: file path
    Returns-->str
    Use if you are not concerned with encosing and want to suppress
    debug messages
    Internally calls file_contents
    '''
    (s, e) = file_contents(f, encoding=None, debug=None)
    return s


def remove_blank_lines(s, remove_comments=True):
    '''
    s-->str
    remove_comments-->bool: If True: removes 'shell style # comments
    Returns-->str: s with lines containing only white space removed
    '''
    comment_pat = re.compile('^\s*#')
    ret = []
    for l in s.splitlines():
        if not l.strip():
            continue
        if remove_comments and re.match(comment_pat, l):
            continue
        ret.append(l)
    return '\n'.join(ret)


class FileWriteSingleton(Singleton):
    '''
    Wrapper to wrap around EITHER a file-like object with a 'write' method
    OR a file path that exists or can be created with parent dir
    '''
    def __init__(
        self, f, encoding=DEFAULT_ENCODING,
        errors=sys.stderr, expanduser=True, expandvars=False
    ):
        '''
        f-->str (file path) OR file-like object opened for writing / appending
            with a 'write' method
        encoding-->str
        errors-->file-like object with a 'write' method
        expanduser-->bool: Expand ~ and ~user constructions
        expandvars-->bool: Expand shell variables of form $var and ${var}
            Unknown variables are LEFT UNCHANGED
            Consider this feature EXPERIMENTAL
        If f is str:
            f is normalized:
                - Collapse multiple / to /
                - Follow symlinks
                - Expand ` and ~user notations if expanduser is True
                - Expand $x and ${x} variables if expandvars is True
            if f exists:
                f is opened for appending
            else:
                if dirname(f) exists:
                    dirname(f)/f is created and opened for appending
            If f does not exist and cannot be created, a single message to that effect
            will be printed to sys.stderr if errors is not None.
            Subsequent calls to FileWriteSingleton.write will fail SILENTLY
        else:
            f is assumed to be a file-like object opened for writing / appending
            with a 'write' method
            The FIRST call to FileWriteSingleton.write will be sent to
            errors if FileWriteSingleton.write fails and errors is not None.
            Subsequent calls to FileWriteSingleton.write will fail SILENTLY

        ONLY the FIRST write error is output to errors (if errors is set),
        TYPICALLY (but not necessarily ONLY) while opening the file (if
        f is str) or during first write (if f is file-like object).

        Some less-common edge cases / effects of this:
            If file is unlinked or permissions are changed to make writes fail
            after the file is successfully opened, the first failed write
            will be written to errors (if set), but subsequent writes WILL
            NOT BE TRIED AT ALL - even if (e.g.) file permissions are restored

            If the filesystem is full and a write fails, the first failed write
            will be written to errors (if set), but subsequent writes WILL
            NOT BE TRIED AT ALL - even if (e.g.) file system is expanded
        '''
        self.__errors = errors
        self.__encoding = encoding
        self.__warned = False
        self.__fd = self.__get_fd(
            f=f, errors=errors, expanduser=expanduser, expandvars=expandvars
        )

        self.__name = '<unknown>'
        try:
            self.__name = self.__fd.name
        except:
            pass

    def __get_fd(self, f, errors=sys.stderr, expanduser=True, expandvars=False):
        '''
        f-->str (file path) OR file-like object opened for writing / appending
            with a 'write' method
        Returns: file-like object or None
        '''
        mode = 'a+'
        encoding = self.__encoding

        if isinstance(f, str):
            p = path_2_nt(f, expanduser=expanduser, expandvars=expandvars)
            if p.exists or p.dir_exists:
                try:
                    if encoding:
                        return open(f, mode=mode, encoding=encoding)
                    else:
                        return open(f, mode=mode)
                except:
                    msg = 'Could not write to %s' % (f,)
                    self.__write_error(msg)
                    return None
            else:
                msg = 'Could not open or create %s' % (f,)
                self.__write_error(msg)
                return None
        else:    # ASSUMED to be a file-like object
            return f

    def __write_error(self, s):
        if not self.__errors or self.__warned:
            return
        try:
            if not s.endswith('\n'):
                s += '\n'
            self.__errors.write(s)
            self.__warned = True
        except:
            pass

    def write(self, s):
        '''s-->str'''
        if not self.__fd:
            self.__write_error('Could not write to %s' % (self.__name,))
            return
        try:
            if not s.endswith('\n'):
                s += '\n'
            self.__fd.write(s)
        except Exception as e:
            if not self.__warned:
                msg = 'Could not write to %s' % (self.__name,)
                self.__write_error(format_exc(e, msg=msg))
