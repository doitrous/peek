#!/bin/bash
# Builds Peek and installs it straight into /Applications/Peek.app, ad-hoc signed
# so macOS shows clean "Peek" permission prompts. Quits any running copy first so
# the bundle can be replaced cleanly.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=".build/release/Peek"
APP="/Applications/Peek.app"

pkill -f "Peek.app/Contents/MacOS/Peek" 2>/dev/null || true
sleep 1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Peek"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Peek</string>
  <key>CFBundleDisplayName</key>     <string>Peek</string>
  <key>CFBundleIdentifier</key>      <string>com.peek.switcher</string>
  <key>CFBundleExecutable</key>      <string>Peek</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key>         <string>1</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSUIElement</key>            <true/>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Prefer the stable self-signed identity (run ./setup-signing.sh once) so TCC
# permission grants persist across rebuilds; fall back to ad-hoc if it's missing.
IDENTITY="Peek Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with stable identity: $IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "Ad-hoc signed (run ./setup-signing.sh for stable grants)."
fi
echo "Installed $APP — launch with:  open $APP"
