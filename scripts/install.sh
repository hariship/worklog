#!/bin/sh
# Builds Worklog and installs it to /Applications, replacing any older copy, then opens it.
# The first launch from /Applications turns on Open at Login (toggle it in Settings).
set -eu
cd "$(dirname "$0")/.."
./scripts/bundle.sh
pkill -f "Worklog.app/Contents/MacOS/Worklog" 2>/dev/null && sleep 1 || true
rm -rf /Applications/Worklog.app
cp -R build/Worklog.app /Applications/Worklog.app
open /Applications/Worklog.app
echo "Installed /Applications/Worklog.app"
