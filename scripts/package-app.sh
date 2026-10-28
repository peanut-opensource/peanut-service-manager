#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

# Select an exact fingerprint; never silently switch certificate identities.
SIGNING_IDENTITY="${PSM_CODESIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  if [[ ! "$SIGNING_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] ||
    ! security find-identity -v -p codesigning | awk '{print $2}' | /usr/bin/grep -Fxiq -- "$SIGNING_IDENTITY"; then
    echo "PSM_CODESIGN_IDENTITY 必须是本机有效代码签名身份的完整 SHA-1 指纹。" >&2
    exit 1
  fi
fi

ARM_TRIPLE="arm64-apple-macosx12.0"
X86_TRIPLE="x86_64-apple-macosx12.0"
swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --triple "$ARM_TRIPLE"
ARM_BIN_DIR="$(swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --triple "$ARM_TRIPLE" --show-bin-path)"
swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --triple "$X86_TRIPLE"
X86_BIN_DIR="$(swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --triple "$X86_TRIPLE" --show-bin-path)"
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
# lipo and strip must finish before signing. Seal nested code before the app.
codesign --force --sign "$SIGNING_IDENTITY" --identifier org.peanutopensource.PeanutServiceManager.supervisor "$CONTENTS/Library/LaunchServices/peanut-service-supervisor"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --all-architectures --strict "$CONTENTS/Library/LaunchServices/peanut-service-supervisor"
codesign --verify --all-architectures --deep --strict "$APP"
plutil -lint "$CONTENTS/Info.plist"
lipo -archs "$CONTENTS/MacOS/peanut-service-manager"
lipo -archs "$CONTENTS/Library/LaunchServices/peanut-service-supervisor"
echo "Created: $APP"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "本地 ad-hoc 签名：此安装可请求隐私授权；重新构建后身份可能变化，需要重新授权。" >&2
fi
