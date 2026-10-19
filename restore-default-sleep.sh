#!/bin/zsh
set -eu

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "Run with sudo, or use Power Management.app." >&2
  exit 1
fi

LABEL="com.yuwangzhi.codex-power-keepawake"
PLIST_DST="/Library/LaunchDaemons/$LABEL.plist"
SCRIPT_DST="/usr/local/sbin/codex-power-keepawake.sh"
SCREENSAVER_DST="/usr/local/sbin/screensaver-settings.sh"
BASE_DIR="${0:A:h}"
source "$BASE_DIR/power-settings.sh"

/bin/launchctl bootout system "$PLIST_DST" 2>/dev/null || true
/bin/launchctl disable "system/$LABEL" 2>/dev/null || true
/bin/rm -f "$PLIST_DST" "$SCRIPT_DST" "$SCREENSAVER_DST"

restore_power_settings
/bin/zsh "$BASE_DIR/screensaver-settings.sh" 1200

echo "Removed $LABEL."
echo "Automatic screen saver restored to 20 minutes."
echo "Current power settings:"
/usr/bin/pmset -g custom
