#!/bin/bash
# Usage: ./build.sh          build build/NotchIsland.app
#        ./build.sh run      build and (re)launch
#        ./build.sh install  build, copy to /Applications and launch
#        ./build.sh dmg      build build/Notch-Island.dmg (drag-to-Applications installer)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Notch Island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchIsland "$APP/Contents/MacOS/NotchIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Use a stable self-signed identity if present so macOS keeps permissions across rebuilds
# (see README → "Keep permissions across rebuilds"); otherwise sign ad-hoc.
IDENTITY="Notch Island Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY" \
   && codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null; then
  echo "Signed with '$IDENTITY'"
else
  codesign --force --sign - "$APP" >/dev/null
  echo "Signed ad-hoc"
fi
echo "Built $APP"

case "${1:-}" in
  run)
    pkill -x NotchIsland 2>/dev/null || true
    sleep 0.3
    open "$APP"
    ;;
  install)
    pkill -x NotchIsland 2>/dev/null || true
    sleep 0.3
    rm -rf "/Applications/Notch Island.app"
    cp -R "$APP" "/Applications/Notch Island.app"
    open "/Applications/Notch Island.app"
    echo "Installed to /Applications"
    ;;
  dmg)
    DMG="build/Notch-Island.dmg"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname "Notch Island" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Built $DMG"
    ;;
esac
