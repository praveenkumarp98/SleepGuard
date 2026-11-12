#!/bin/sh
# Runs every 60 s via launchd. If sleep is blocked while SleepGuard isn't running
# (crash, force-quit, or a raw `sudo pmset`), turn sleep back on.
/usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | /usr/bin/grep -q '"SleepDisabled" = Yes' || exit 0
/usr/bin/pgrep -xq SleepGuard && exit 0
/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0
