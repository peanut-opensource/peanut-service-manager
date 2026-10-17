#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

build_for_arch() {
  local arch="$1"
  local triple="${arch}-apple-macosx12.0"
  swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --triple "$triple"
  swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --triple "$triple" --show-bin-path
}

ARM_BIN_DIR="$(build_for_arch arm64 | tail -n 1)"
X86_BIN_DIR="$(build_for_arch x86_64 | tail -n 1)"
APP="$ROOT/build/Peanut Service Manager.app"
CONTENTS="$APP/Contents"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Library/LaunchServices"
cp "$ROOT/resources/Info.plist" "$CONTENTS/Info.plist"
lipo -create "$ARM_BIN_DIR/peanut-service-manager" "$X86_BIN_DIR/peanut-service-manager" -output "$CONTENTS/MacOS/peanut-service-manager"
lipo -create "$ARM_BIN_DIR/peanut-service-supervisor" "$X86_BIN_DIR/peanut-service-supervisor" -output "$CONTENTS/Library/LaunchServices/peanut-service-supervisor"
strip -x "$CONTENTS/MacOS/peanut-service-manager"
strip -x "$CONTENTS/Library/LaunchServices/peanut-service-supervisor"
ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/generate-app-icons.swift" "$ICONSET" "$CONTENTS/Resources/MenuBarIcon.png"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
chmod 755 "$CONTENTS/MacOS/peanut-service-manager" "$CONTENTS/Library/LaunchServices/peanut-service-supervisor"
plutil -lint "$CONTENTS/Info.plist"
lipo -archs "$CONTENTS/MacOS/peanut-service-manager"
lipo -archs "$CONTENTS/Library/LaunchServices/peanut-service-supervisor"
echo "Created: $APP"
