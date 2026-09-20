#!/bin/bash
# Regenerates the README screenshots (docs/images/) from the real UI: launches Peek
# in PEEK_SHOWCASE mode (mock data, real windows), captures each window, then quits.
# Needs Screen Recording permission for the terminal running this.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=".build/release/Peek"
OUT="docs/images"
mkdir -p "$OUT"

pkill -f "$BIN" 2>/dev/null || true
sleep 1
PEEK_SHOWCASE=1 "$BIN" >/dev/null 2>&1 &
APP=$!
trap 'kill "$APP" 2>/dev/null || true' EXIT
sleep 4

# Map Peek's on-screen windows to files by width (switcher 380 / settings 640 / dashboard 920).
LIST="$(cat <<'SWIFT' | swift -
import CoreGraphics
import Foundation
let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Peek" {
    let num = w[kCGWindowNumber as String] as? Int ?? 0
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let width = Int(b["Width"] ?? 0), height = Int(b["Height"] ?? 0)
    if width > 60, height > 60 { print("\(num) \(width)") }
}
SWIFT
)"

while read -r id width; do
  case "$width" in
    3[0-9][0-9]|4[01][0-9]) name="switcher" ;;
    6[0-9][0-9]) name="settings" ;;
    *) name="dashboard" ;;
  esac
  screencapture -o -l "$id" "$OUT/$name.png"
  echo "captured $OUT/$name.png (window $id, ${width}pt wide)"
done <<< "$LIST"

cp Resources/AppIcon.png "$OUT/icon.png"
echo "Done → $OUT"
