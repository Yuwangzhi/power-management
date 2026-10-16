#!/bin/zsh
set -u

LABEL="com.yuwangzhi.codex-power-keepawake"

echo "=== pmset -g custom ==="
/usr/bin/pmset -g custom

echo
echo "=== pmset -g batt ==="
/usr/bin/pmset -g batt

echo
echo "=== SleepDisabled ==="
/usr/bin/pmset -g | /usr/bin/grep -E 'SleepDisabled|sleep|disksleep|displaysleep' || true

echo
echo "=== LaunchDaemon ==="
if /bin/launchctl print "system/$LABEL" >/tmp/codex-power-launchd-status.$$ 2>&1; then
  /usr/bin/sed -n '1,80p' /tmp/codex-power-launchd-status.$$
else
  echo "$LABEL is not loaded."
  /bin/cat /tmp/codex-power-launchd-status.$$ 2>/dev/null || true
fi
/bin/rm -f /tmp/codex-power-launchd-status.$$
