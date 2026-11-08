#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-$(uname -m)}"
"$ROOT/scripts/build.sh" "$ARCH"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ishot-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/dist/ishot.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/INSTALL.zh-CN.md" "$STAGE/安装说明.txt"
cp "$ROOT/docs/INSTALL.en.md" "$STAGE/INSTALL-English.txt"
DMG="$ROOT/dist/ishot-0.1.0-$ARCH.dmg"
hdiutil create -volname "ishot 0.1.0" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
(cd "$ROOT/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Packaged $DMG"
