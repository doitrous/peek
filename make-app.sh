#!/bin/bash
# Builds Peek and installs it into /Applications/Peek.app.
#
# Signing (best identity available, in order):
#   1. Developer ID Application  -> Hardened Runtime + timestamp (notarizable).
#      Set NOTARIZE=1 (with credentials, see below) to also notarize + staple
#      and emit a distributable dist/Peek.zip.
#   2. "Peek Local Signing"      -> stable self-signed cert (run ./setup-signing.sh).
#   3. ad-hoc                    -> fallback so it always builds locally.
#
# Notarization needs App Store Connect credentials. Store them once with:
#   xcrun notarytool store-credentials peek-notary \
#     --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-pw>
# then build with:  NOTARIZE=1 NOTARY_PROFILE=peek-notary ./make-app.sh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=".build/release/Peek"
APP="/Applications/Peek.app"

pkill -f "Peek.app/Contents/MacOS/Peek" 2>/dev/null || true
sleep 1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Peek"

# Build AppIcon.icns from the 1024px source (all sizes macOS expects).
if [[ -f Resources/AppIcon.png ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size"       Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
    sips -z $((size*2)) $((size*2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Peek</string>
  <key>CFBundleDisplayName</key>     <string>Peek</string>
  <key>CFBundleIdentifier</key>      <string>com.peek.switcher</string>
  <key>CFBundleExecutable</key>      <string>Peek</string>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>CFBundleIconName</key>        <string>AppIcon</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key>         <string>1</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSUIElement</key>            <true/>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# --- Sign -------------------------------------------------------------------
# Look for a real Developer ID Application cert first (the only kind that can be
# notarized for distribution); otherwise the stable self-signed identity; else ad-hoc.
DEVID="$(security find-identity -v -p codesigning 2>/dev/null \
         | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
ENTITLEMENTS="Peek.entitlements"

if [[ -n "$DEVID" ]]; then
  codesign --force --options runtime --timestamp \
           --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$APP"
  echo "Signed (Hardened Runtime) with: $DEVID"
elif security find-certificate -c "Peek Local Signing" >/dev/null 2>&1; then
  codesign --force --deep --sign "Peek Local Signing" "$APP"
  echo "Signed with stable self-signed identity: Peek Local Signing (not distributable)."
else
  codesign --force --deep --sign - "$APP"
  echo "Ad-hoc signed (run ./setup-signing.sh for stable grants; not distributable)."
fi

# --- Notarize + staple (opt-in, needs a Developer ID signature) --------------
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  if [[ -z "$DEVID" ]]; then
    echo "NOTARIZE=1 but no Developer ID Application cert found — create one in" >&2
    echo "Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + Developer ID Application." >&2
    exit 1
  fi
  mkdir -p dist
  ZIP="dist/Peek.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Submitting to Apple notary service…"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
    xcrun notarytool submit "$ZIP" --apple-id "$NOTARY_APPLE_ID" \
          --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" --wait
  else
    echo "No notary credentials. Set NOTARY_PROFILE, or NOTARY_APPLE_ID/PASSWORD/TEAM_ID." >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip the stapled bundle for release
  echo "Notarized + stapled. Distributable archive: $ZIP"
fi

echo "Installed $APP — launch with:  open $APP"
