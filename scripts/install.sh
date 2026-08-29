#!/bin/zsh
set -euo pipefail

REPOSITORY="1070124410/LaunchScope"
ARCHIVE_URL="https://github.com/$REPOSITORY/releases/latest/download/LaunchScope.zip"
CHECKSUM_URL="$ARCHIVE_URL.sha256"
INSTALL_PATH="/Applications/LaunchScope.app"
TEMP_DIR=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$TEMP_DIR"' EXIT

echo "Downloading LaunchScope…"
/usr/bin/curl -fL "$ARCHIVE_URL" -o "$TEMP_DIR/LaunchScope.zip"
/usr/bin/curl -fL "$CHECKSUM_URL" -o "$TEMP_DIR/LaunchScope.zip.sha256"

EXPECTED=$(/usr/bin/awk '{print $1}' "$TEMP_DIR/LaunchScope.zip.sha256")
ACTUAL=$(/usr/bin/shasum -a 256 "$TEMP_DIR/LaunchScope.zip" | /usr/bin/awk '{print $1}')
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "Checksum verification failed." >&2
  exit 1
fi

/usr/bin/ditto -x -k "$TEMP_DIR/LaunchScope.zip" "$TEMP_DIR/unpacked"
if [[ -e "$INSTALL_PATH" ]]; then
  /bin/rm -rf "$INSTALL_PATH"
fi
/usr/bin/ditto "$TEMP_DIR/unpacked/LaunchScope.app" "$INSTALL_PATH"
echo "Installed $INSTALL_PATH"
echo "If macOS blocks the first launch, right-click LaunchScope in Finder and choose Open."
