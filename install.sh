#!/bin/zsh
set -eu

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "Run with sudo, or use Power Management.app." >&2
  exit 1
fi

BASE_DIR="${0:A:h}"
SCRIPT_SRC="$BASE_DIR/codex-power-keepawake.sh"
PLIST_SRC="$BASE_DIR/com.yuwangzhi.codex-power-keepawake.plist"
SCREENSAVER_SRC="$BASE_DIR/screensaver-settings.sh"

SCRIPT_DST="/usr/local/sbin/codex-power-keepawake.sh"
PLIST_DST="/Library/LaunchDaemons/com.yuwangzhi.codex-power-keepawake.plist"
SCREENSAVER_DST="/usr/local/sbin/screensaver-settings.sh"
LABEL="com.yuwangzhi.codex-power-keepawake"

source "$BASE_DIR/power-settings.sh"
capture_power_settings
SCREENSAVER_PREVIOUS="$(/bin/zsh "$SCREENSAVER_SRC" read)"
INSTALL_SUCCESS=0
trap 'if [[ "$INSTALL_SUCCESS" == 0 ]]; then
  print -u2 "Installation failed; restoring the previous power settings."
  /bin/zsh "$BASE_DIR/restore-default-sleep.sh" >&2 || true
  if [[ "$SCREENSAVER_PREVIOUS" == <-> ]]; then
    /bin/zsh "$SCREENSAVER_SRC" "$SCREENSAVER_PREVIOUS" >&2 || true
  fi
fi' EXIT

/usr/bin/install -d -o root -g wheel -m 755 /usr/local/sbin
/usr/bin/install -o root -g wheel -m 755 "$SCRIPT_SRC" "$SCRIPT_DST"
/usr/bin/install -o root -g wheel -m 755 "$SCREENSAVER_SRC" "$SCREENSAVER_DST"
/usr/bin/install -o root -g wheel -m 644 "$PLIST_SRC" "$PLIST_DST"

"$SCRIPT_DST"

/bin/launchctl bootout system "$PLIST_DST" 2>/dev/null || true
/bin/launchctl enable "system/$LABEL"
/bin/launchctl bootstrap system "$PLIST_DST"
/bin/launchctl kickstart -k "system/$LABEL"
INSTALL_SUCCESS=1

echo "Installed and enabled $LABEL"
echo "Current power settings:"
/usr/bin/pmset -g custom
