#!/bin/zsh
set -euo pipefail

# Legacy CLI entrypoint. Daily use is now the native Power Management app.
BASE_DIR="${0:A:h}"
if [[ -e /Library/LaunchDaemons/com.yuwangzhi.codex-power-keepawake.plist ]]; then
  TARGET_SCRIPT="$BASE_DIR/restore-default-sleep.sh"
else
  TARGET_SCRIPT="$BASE_DIR/install.sh"
fi
TARGET_ESCAPED="$(printf '%s' "$TARGET_SCRIPT" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
/usr/bin/osascript <<OSA
set targetScript to "$TARGET_ESCAPED"
do shell script "/bin/zsh " & quoted form of targetScript with administrator privileges
OSA
