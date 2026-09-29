#!/bin/sh
# Builds a release binary and wraps it in build/Worklog.app (menu bar only, no Dock icon).
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Worklog.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Worklog "$APP/Contents/MacOS/Worklog"

# App icon, drawn by scripts/make_icon.swift and cached in build/.
if [ ! -f build/AppIcon.icns ] || [ scripts/make_icon.swift -nt build/AppIcon.icns ]; then
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make_icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2)); sips -z $d $d build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
mkdir -p "$APP/Contents/Resources"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Worklog</string>
  <key>CFBundleIdentifier</key><string>io.hariship.worklog</string>
  <key>CFBundleExecutable</key><string>Worklog</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Worklog adds your #weekly lines and a weekly summary to a note in Apple Notes.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
