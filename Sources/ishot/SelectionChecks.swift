import AppKit
import IShotCore

/// UI event regression checks; use a generated image, never the user's desktop.
@MainActor func runSelectionChecks(image: CGImage, outputDirectory: URL?) {
    let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 1000, height: 640), image: image, method: .drag)
    let panel = KeyPanel(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false; panel.acceptsMouseMovedEvents = true; panel.contentView = view
    defer { panel.close() }
    func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 640 - y), modifierFlags: flags, timestamp: 600, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    func click(_ x: CGFloat, _ y: CGFloat, flags: NSEvent.ModifierFlags = []) {
        view.mouseDown(with: mouse(.leftMouseDown, x, y, flags: flags))
        view.mouseUp(with: mouse(.leftMouseUp, x, y))
    }
    func key(_ characters: String, _ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1200, windowNumber: panel.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }
    func snapshot(_ name: String) {
        guard let outputDirectory else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure("Cannot render selection") }
        view.cacheDisplay(in: view.bounds, to: rep)
        do { try rep.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent(name)) }
        catch { preconditionFailure("Cannot save selection snapshot: \(error)") }
    }
    view.mouseDown(with: mouse(.leftMouseDown, 40, 110))
    view.mouseDragged(with: mouse(.leftMouseDragged, 800, 450))
    view.mouseUp(with: mouse(.leftMouseUp, 800, 450))
    precondition(view.isSelectionReady && view.isToolbarVisible)
    precondition(view.selection == CGRect(x: 40, y: 110, width: 760, height: 340))
    snapshot("selection.png")
    view.resetSelection()
    click(40, 110, flags: .option)
    precondition(view.isWaitingForSecondPoint && !view.isToolbarVisible && !view.isSelectionReady)
    // Motion with no pressed button and no Option must update the live rectangle.
    view.mouseMoved(with: mouse(.mouseMoved, 800, 450))
    precondition(view.selection == CGRect(x: 40, y: 110, width: 760, height: 340))
    snapshot("two-point-preview.png")
    view.mouseMoved(with: mouse(.mouseMoved, 258, 181)); snapshot("magnifier-detail.png")
    view.mouseMoved(with: mouse(.mouseMoved, 999, 639)); snapshot("magnifier-edge.png")
    view.mouseMoved(with: mouse(.mouseMoved, 800, 450))
    var completed = 0
    view.complete = { _, _ in completed += 1 }
    view.keyDown(with: key("p", 35)); view.keyDown(with: key("c", 8)); view.keyDown(with: key("s", 1)); view.keyDown(with: key("\r", 36))
    precondition(completed == 0, "An unfinished preview must never be exported")
    view.keyDown(with: key("\u{7f}", 51))
    precondition(!view.isWaitingForSecondPoint && view.selection == .zero && !view.isToolbarVisible)
    // Delete keeps the temporary two-point mode, so Option need not be held again.
    click(800, 450); precondition(view.isWaitingForSecondPoint)
    view.mouseMoved(with: mouse(.mouseMoved, 40, 110)); click(40, 110)
    precondition(view.isSelectionReady && view.isToolbarVisible)
    precondition(view.selection == CGRect(x: 40, y: 110, width: 760, height: 340))
    snapshot("two-point-complete.png")
    view.mouseDown(with: mouse(.leftMouseDown, 200, 200))
    view.mouseDragged(with: mouse(.leftMouseDragged, 220, 220))
    view.mouseUp(with: mouse(.leftMouseUp, 220, 220))
    precondition(view.selection == CGRect(x: 60, y: 130, width: 760, height: 340))
    view.mouseDown(with: mouse(.leftMouseDown, 820, 470))
    view.mouseDragged(with: mouse(.leftMouseDragged, 800, 450))
    view.mouseUp(with: mouse(.leftMouseUp, 800, 450))
    precondition(view.selection == CGRect(x: 60, y: 130, width: 740, height: 320))
    view.complete = { rect, action in
        let pixels = Geometry.pixelRect(rect, viewSize: view.bounds.size, pixels: CGSize(width: image.width, height: image.height))
        precondition(image.cropping(to: pixels)?.width == 740)
        precondition(image.cropping(to: pixels)?.height == 320)
        precondition(action == .pin); completed += 1
    }
    view.keyDown(with: key("p", 35)); precondition(completed == 1)
    var cancelled = false; view.cancel = { cancelled = true }
    view.keyDown(with: key("\u{1b}", 53)); precondition(cancelled)
    print("SELECTION UI PASS: drag, Option latch, free hover, Delete, reverse corners, delayed export, toolbar, move/resize, pixel crop, Escape")
}
