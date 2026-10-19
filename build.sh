#!/bin/zsh
set -euo pipefail

BASE_DIR="${0:A:h}"
BUILD_DIR="$BASE_DIR/.build"
APP="$BUILD_DIR/Power Management.app"
VERSION="$(/bin/cat "$BASE_DIR/VERSION")"
ARCH="$(/usr/bin/uname -m)"
if [[ "${1:-}" == "--universal" ]]; then
  ARCH="universal"
fi
/bin/mkdir -p "$BUILD_DIR" "$APP/Contents/MacOS" "$APP/Contents/Resources/Scripts"

if [[ "$ARCH" == "universal" ]]; then
  for target_arch in arm64 x86_64; do
    /usr/bin/xcrun swiftc -O -swift-version 5 -target "$target_arch-apple-macos13.0" \
      -module-cache-path "$BUILD_DIR/ModuleCache" -framework AppKit -framework SwiftUI \
      "$BASE_DIR/Sources/PowerCore.swift" "$BASE_DIR/Sources/PowerManagement.swift" \
      -o "$BUILD_DIR/PowerManagement-$target_arch"
  done
  /usr/bin/lipo -create "$BUILD_DIR/PowerManagement-arm64" "$BUILD_DIR/PowerManagement-x86_64" -output "$APP/Contents/MacOS/PowerManagement"
else
  /usr/bin/xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" \
    -module-cache-path "$BUILD_DIR/ModuleCache" -framework AppKit -framework SwiftUI \
    "$BASE_DIR/Sources/PowerCore.swift" "$BASE_DIR/Sources/PowerManagement.swift" \
    -o "$APP/Contents/MacOS/PowerManagement"
fi

/bin/cp "$BASE_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
for script in install.sh restore-default-sleep.sh codex-power-keepawake.sh power-settings.sh screensaver-settings.sh com.yuwangzhi.codex-power-keepawake.plist; do
  /bin/cp "$BASE_DIR/$script" "$APP/Contents/Resources/Scripts/$script"
done
/bin/chmod 755 "$APP/Contents/Resources/Scripts/"*.sh

ICON="$BASE_DIR/Resources/AppIcon.png"
if [[ ! -f "$ICON" ]]; then
  print -u2 "Missing icon: $ICON"
  exit 1
fi
ICONSET="$BUILD_DIR/AppIcon.iconset"
/bin/mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  /usr/bin/sips -z "$double_size" "$double_size" "$ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --strict "$APP"
print "Built $APP ($VERSION, $ARCH)"

if [[ "${1:-}" == "--install" || "${2:-}" == "--install" ]]; then
  DEST="/Applications/Power Management.app"
  if /usr/bin/pgrep -x PowerManagement >/dev/null; then
    /usr/bin/pkill -TERM -x PowerManagement
    for attempt in {1..30}; do
      /usr/bin/pgrep -x PowerManagement >/dev/null || break
      /bin/sleep 0.1
    done
    if /usr/bin/pgrep -x PowerManagement >/dev/null; then
      print -u2 "Power Management is still running; installation stopped."
      exit 1
    fi
  fi
  if [[ -e "$DEST" ]]; then
    BACKUP="$HOME/Library/Application Support/Power Management/Backups/app-$(/bin/date +%Y%m%d-%H%M%S)-$$.zip"
    /bin/mkdir -p "${BACKUP:h}"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DEST" "$BACKUP"
    /usr/bin/unzip -tq "$BACKUP" >/dev/null
    PREVIOUS="$HOME/.Trash/Power-Management-previous-$(/bin/date +%Y%m%d-%H%M%S)-$$.app"
    /bin/mkdir -p "$HOME/.Trash"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$DEST"
    /bin/mv "$DEST" "$PREVIOUS"
    if ! /usr/bin/ditto "$APP" "$DEST"; then
      if [[ -e "$DEST" ]]; then
        /bin/mv "$DEST" "$HOME/.Trash/Power-Management-failed-$(/bin/date +%Y%m%d-%H%M%S)-$$.app"
      fi
      /bin/mv "$PREVIOUS" "$DEST"
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
      print -u2 "Install failed; previous App was restored."
      exit 1
    fi
  else
    /usr/bin/ditto "$APP" "$DEST"
  fi
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  /usr/bin/mdimport "$DEST"
  for launcher in '查看电源状态' '切换-不睡眠不断SSH'; do
    /usr/bin/osacompile -o "$BASE_DIR/$launcher.app" "$BASE_DIR/$launcher.applescript"
  done
  print "Installed $DEST"
fi
