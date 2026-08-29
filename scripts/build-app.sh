#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
APP_DIR="$PROJECT_DIR/dist/LaunchScope.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
swift build -c release --product BackgroundButler
BIN_DIR=$(swift build -c release --show-bin-path)

if [[ "$APP_DIR" != "$PROJECT_DIR/dist/LaunchScope.app" ]]; then
  echo "Unexpected app output path" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
ditto "$BIN_DIR/BackgroundButler" "$CONTENTS_DIR/MacOS/BackgroundButler"
ditto "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$PROJECT_DIR/Packaging/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
