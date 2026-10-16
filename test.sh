#!/bin/zsh
set -euo pipefail
BASE_DIR="${0:A:h}"
/bin/mkdir -p "$BASE_DIR/.build"
for script in "$BASE_DIR/"*.sh; do
  /bin/zsh -n "$script"
done
/usr/bin/plutil -lint "$BASE_DIR/Resources/Info.plist" "$BASE_DIR/com.yuwangzhi.codex-power-keepawake.plist"
/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$BASE_DIR/.build/ModuleCache" \
  "$BASE_DIR/Sources/PowerCore.swift" "$BASE_DIR/Tests/PowerCoreTests.swift" -o "$BASE_DIR/.build/PowerCoreTests"
"$BASE_DIR/.build/PowerCoreTests"
/usr/bin/python3 "$BASE_DIR/Tests/test_power_scripts.py"
for script in install.sh restore-default-sleep.sh; do
  if /bin/zsh "$BASE_DIR/$script" > "$BASE_DIR/.build/root-guard.log" 2>&1; then
    print -u2 "$script unexpectedly accepted an unprivileged invocation"
    exit 1
  fi
  /usr/bin/grep -q 'Run with sudo' "$BASE_DIR/.build/root-guard.log"
done
print "Script syntax, plists and privilege guards passed. No system power settings were changed."
