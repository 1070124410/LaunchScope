#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
APP_PATH="$PROJECT_DIR/dist/LaunchScope.app"
ARCHIVE_PATH="$PROJECT_DIR/dist/LaunchScope.zip"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

if [[ ! -d "$APP_PATH" ]]; then
  "$PROJECT_DIR/scripts/build-app.sh"
fi

rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
cd "$PROJECT_DIR/dist"
/usr/bin/shasum -a 256 "LaunchScope.zip" > "LaunchScope.zip.sha256"
echo "$ARCHIVE_PATH"
echo "$CHECKSUM_PATH"
