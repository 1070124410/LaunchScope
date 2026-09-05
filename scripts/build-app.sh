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
AI_DIR="$CONTENTS_DIR/Resources/LaunchScopeAI"
mkdir -p "$AI_DIR"
ditto "$PROJECT_DIR/mcp/launchscope_mcp.py" "$AI_DIR/launchscope_mcp.py"
ditto "$PROJECT_DIR/.agents/skills/launchscope/scripts/rules_tool.py" "$AI_DIR/rules_tool.py"
ditto "$PROJECT_DIR/.agents/skills/launchscope/SKILL.md" "$AI_DIR/SKILL.md"
ditto "$PROJECT_DIR/docs/AGENT_PROTOCOL.md" "$AI_DIR/AGENT_PROTOCOL.md"
ditto "$PROJECT_DIR/docs/schema/purpose-rules-v1.schema.json" "$AI_DIR/purpose-rules-v1.schema.json"
chmod 755 "$AI_DIR/launchscope_mcp.py" "$AI_DIR/rules_tool.py"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
