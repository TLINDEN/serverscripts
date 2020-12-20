#!/bin/sh

ports=$1
ts=`date +%Y%m%d`
cpdup /etc /usr/backups/etc-%ts
cpdup /usr/local/etc /usr/backups/usr-local-etc-%ts

if test -z "$ports"; then
    freebsd-update fetch
    freebsd-update install || freebsd-update rollback

    if test "x`freebsd-version -k`" != "x`uname -r`"; then
        echo -n "Reboot required. Reboot now [Yn]? "
        read yesno
        case $yesno in
            n|N|no|NO)
                echo "ok, then reboot manually at a later time!"
                ;;
            *)
                shutdown -r now
                ;;
        esac
    fi
else
    pkg upgrade
fi
