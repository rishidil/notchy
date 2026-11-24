#!/bin/bash
# Usage: ./build.sh          build build/Notchy.app
#        ./build.sh run      build and (re)launch
#        ./build.sh install  build, copy to /Applications and launch
#        ./build.sh dmg      build build/Notchy.dmg (drag-to-Applications installer)
#        ./build.sh release  Developer ID-signed, notarized DMG for public download (see README → "Releasing")
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Notchy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchIsland "$APP/Contents/MacOS/Notchy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Use a stable self-signed identity if present so macOS keeps permissions across rebuilds
# (see README → "Keep permissions across rebuilds"); otherwise sign ad-hoc.
DEVID=$(security find-identity -p codesigning -v 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
IDENTITY="Notch Island Dev"
if [ "${1:-}" = "release" ]; then
  # Public release: Developer ID + Hardened Runtime + secure timestamp (all required for notarization).
  if [ -z "$DEVID" ]; then
    echo "No 'Developer ID Application' certificate found. See README → Releasing." >&2
    exit 1
  fi
  codesign --force --options runtime --timestamp --entitlements Resources/Notchy.entitlements --sign "$DEVID" "$APP"
  echo "Signed with '$DEVID'"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY" \
   && codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null; then
  echo "Signed with '$IDENTITY'"
else
  codesign --force --sign - "$APP" >/dev/null
  echo "Signed ad-hoc"
fi
echo "Built $APP"

case "${1:-}" in
  run)
    pkill -x Notchy 2>/dev/null || true
    pkill -x NotchIsland 2>/dev/null || true
    sleep 0.3
    open "$APP"
    ;;
  install)
    pkill -x Notchy 2>/dev/null || true
    pkill -x NotchIsland 2>/dev/null || true
    sleep 0.3
    rm -rf "/Applications/Notchy.app" "/Applications/Notch Island.app" # (old name)
    cp -R "$APP" "/Applications/Notchy.app"
    open "/Applications/Notchy.app"
    echo "Installed to /Applications"
    ;;
  release)
    DMG="build/Notchy.dmg"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname "Notchy" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$STAGE"
    codesign --force --timestamp --sign "$DEVID" "$DMG"
    echo "Submitting to Apple for notarization (usually 1–5 minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-notchy}" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    echo "Ready: $DMG is signed, notarized and stapled. Upload it to a GitHub release."
    ;;
  dmg)
    DMG="build/Notchy.dmg"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname "Notchy" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Built $DMG"
    ;;
esac
