#!/bin/zsh
set -euo pipefail
BASE_DIR="${0:A:h}"
VERSION="$(/bin/cat "$BASE_DIR/VERSION")"
/bin/zsh "$BASE_DIR/build.sh" --universal
/bin/mkdir -p "$BASE_DIR/dist"
ZIP="$BASE_DIR/dist/Power-Management-$VERSION-universal.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$BASE_DIR/.build/Power Management.app" "$ZIP"
cd "$BASE_DIR/dist"
/usr/bin/shasum -a 256 "${ZIP:t}" > SHA256SUMS.txt
print "$ZIP"
