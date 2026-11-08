# Install ishot 0.1.0

Requires macOS 14 or later. The universal DMG includes both Apple Silicon and Intel binaries; runtime testing has only been performed on Apple Silicon. The app UI is currently in Simplified Chinese.

1. Download `ishot-0.1.0-universal.dmg` from https://github.com/sunholdshen/ishot/releases/tag/v0.1.0.
2. Open the DMG and drag `ishot.app` into Applications.
3. Open ishot from Applications. Look for its viewfinder icon in the top menu bar.
4. Click “开始截图” (Start capture), then allow Screen Recording permission. If capture still fails, quit and reopen ishot after granting permission.
5. Drag a region and press P to pin, Enter to annotate, C to copy, S to save, or Esc to cancel.

## First launch and signing

This preview is ad-hoc signed, not Developer ID signed or notarized. macOS may block an app downloaded through a browser. If you trust this repository and the downloaded file matches its checksum, follow Apple's instructions to choose Open Anyway for this app in System Settings → Privacy & Security. Wording and availability depend on the OS and device policy. Do not disable system-wide security checks.

Apple's official guide: https://support.apple.com/en-us/102445

To check integrity, download the matching `.sha256` file next to the DMG and run:

    shasum -a 256 -c ishot-0.1.0-universal.dmg.sha256

## Shortcuts and pins

- Region capture: Command + Shift + Option + 3
- Capture the display under the pointer: Command + Shift + Option + 4
- Show / hide all pins: Command + Shift + Option + P
- Drag a pin to move it; scroll or pinch to resize.
- Option + scroll changes opacity; double-click restores the original display size within screen limits.
- Right-click for annotation, copy, save, lock, and close.
- Save needed images before quitting; pins are not restored on restart.

Change shortcuts in “设置 → 快捷键” (Settings → Shortcuts). Duplicate or occupied combinations are rejected. Screen Recording settings are linked from “设置 → 通用” (Settings → General); Accessibility permission is not required.

## Build instead

    xcode-select --install
    git clone https://github.com/sunholdshen/ishot.git
    cd ishot
    ./scripts/build.sh universal

Move `dist/ishot.app` into Applications. See README.en.md for development instructions and known limitations.
