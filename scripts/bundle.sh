#!/bin/sh
# Builds a release binary and wraps it in build/Worklog.app (menu bar only, no Dock icon).
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Worklog.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Worklog "$APP/Contents/MacOS/Worklog"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Worklog</string>
  <key>CFBundleIdentifier</key><string>io.hariship.worklog</string>
  <key>CFBundleExecutable</key><string>Worklog</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Worklog adds your #weekly lines and a weekly summary to a note in Apple Notes.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
