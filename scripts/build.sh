#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-$(uname -m)}"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" && "$ARCH" != "universal" ]]; then
  echo "Usage: scripts/build.sh [arm64|x86_64|universal]" >&2; exit 2
fi
BUILD_DIR="${ISHOT_BUILD_PATH:-$ROOT/.build}"
DIST="$ROOT/dist"
APP="$DIST/ishot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$ARCH" == "universal" ]]; then
  swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --product ishot --arch arm64
  swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --product ishot --arch x86_64
  lipo -create "$BUILD_DIR/arm64-apple-macosx/release/ishot" "$BUILD_DIR/x86_64-apple-macosx/release/ishot" -output "$APP/Contents/MacOS/ishot"
else
  swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --product ishot --arch "$ARCH"
  cp "$BUILD_DIR/$ARCH-apple-macosx/release/ishot" "$APP/Contents/MacOS/ishot"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"; fi
# Ad-hoc signing enables local execution. It is not Developer ID signing or notarization.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($ARCH, ad-hoc signed)"
