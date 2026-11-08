# Architecture

The executable uses AppKit directly for predictable borderless windows, responder routing and the native menu bar. There are no third-party dependencies or network clients.

## Capture

`CaptureCoordinator` obtains display snapshots through ScreenCaptureKit's macOS 14 screenshot API. Each NSScreen is matched by CGDirectDisplayID, so display arrangements (including negative global origins) do not change local crop coordinates. Output dimensions use each screen's backing scale. The current process is excluded from captures. Region selection operates on immutable snapshots, not live screen content.

Each display receives a borderless overlay. Geometry maps top-left view points to top-left bitmap pixels, clips to bounds and rounds outward. A region is restricted to one display. Escape and display topology changes release every overlay. A busy flag prevents concurrent captures. ScreenCaptureKit requests screen recording authorization; no Accessibility or Input Monitoring permission is used.

## Selection interaction

`SelectionModel` is a UI-independent state machine for drag, first-click, hover preview, second-click, movement, and corner resizing. An Option-click latches two-point mode for the current capture only. The saved preference is read at the start of each capture. Mouse-up after the first point cannot finalize a region; export actions require a valid, completed rectangle. A four-point motion threshold distinguishes a deliberate drag from click jitter when two-point is the default. Delete clears the first anchor while retaining the session mode.

The overlay accepts mouse-moved events without pressed buttons and requests mouse-moved tracking. A first anchor prevents another display's overlay from accepting the second point. A magnifier samples a 17 × 17 bitmap-pixel patch from the immutable image using nearest-neighbor rendering; source coordinates and on-screen placement are clamped at edges. No live recapture is performed for magnification.

## Annotation

`ImageDocument` stores a CGImage and value-type annotations. A bounded undo / redo stack shares CGImage references and copies annotation arrays using Swift's copy-on-write storage. Drawing and export share the same top-left coordinate transform. Cropping flattens existing marks, but retains the previous image and marks for undo. Covers force alpha to 1. Export allocates an sRGB RGBA bitmap at source pixel dimensions, then encodes PNG.

## Pins

Every pin has an independent nonactivating NSPanel at floating level. Pins join desktop spaces and opt into full-screen auxiliary behavior. They have no title bar, do not appear in the Dock and expose controls on hover. The app retains window controllers by UUID, releasing them asynchronously on close to avoid controller deallocation during AppKit delegate callbacks. A pin editor starts from the current flattened image; applying edits updates the same pin.

## Settings and shortcuts

Three Carbon RegisterEventHotKey registrations avoid global event taps. Shortcut changes reject duplicates, register as a group and roll back on conflict. Preferences are stored with UserDefaults. Login startup uses SMAppService.mainApp and reports system approval requirements instead of silently assuming success.

## Distribution

SwiftPM produces a command-line Mach-O executable which the build script wraps in a conventional `.app`. Info.plist sets LSUIElement and macOS 14 minimum. Universal binaries are combined with lipo. The bundle is ad-hoc signed and verified, but has no Developer ID certificate or notarization. The packaging script creates a read-only compressed DMG with an Applications link and SHA-256 checksum.

References:
- https://developer.apple.com/documentation/ScreenCaptureKit/SCScreenshotManager/captureImage(contentFilter:configuration:completionHandler:)
- https://developer.apple.com/documentation/servicemanagement/smappservice/register()
