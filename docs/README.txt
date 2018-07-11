When starting with a new BASE config (e.g. from Ubuntu), MAKE SURE
to set
    CONFIG_DEBUG_INFO=n

Otherwise compilation will use a LOT of disk space (20G instead of 2G)
and will take a LONG time.

See: http://superuser.com/a/925482
