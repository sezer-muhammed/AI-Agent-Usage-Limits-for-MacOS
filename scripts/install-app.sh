#!/bin/bash
# Build, install and relaunch AI Meter.
#
# The widget step matters: macOS keeps running the previously registered
# extension binary, so a reinstall alone leaves the old widget code rendering
# new data — which looks like a design bug and is not one.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
APP="/Applications/AI Meter.app"
BUILT=".build/xcode/Build/Products/$CONFIG/AI Meter.app"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration "$CONFIG" \
    -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

pkill -x "AI Meter" 2>/dev/null || true
pkill -f AIMeterWidget 2>/dev/null || true

rm -rf "$APP"
cp -R "$BUILT" /Applications/

# Re-register the extension and restart the widget host, so the desktop widget
# picks up the new binary instead of the cached one.
pluginkit -a "$APP/Contents/PlugIns/AIMeterWidget.appex" 2>/dev/null || true
killall chronod 2>/dev/null || true

open "$APP"
echo "Installed and relaunched: $APP"
