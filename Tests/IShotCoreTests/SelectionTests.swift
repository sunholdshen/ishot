import Foundation
import IShotCore

final class SelectionTests {
    private let size = CGSize(width: 1000, height: 700)
    private let a = CGPoint(x: 40, y: 50), b = CGPoint(x: 800, y: 600)
    func testOptionLatchesUntilSecondClick() {
        var model = SelectionModel(size: size)
        model.press(a, option: true); model.release(a)
        expectEqual(model.anchor, a); expectFalse(model.isReady)
        model.hover(b)
        expectEqual(model.rect, CGRect(x: 40, y: 50, width: 760, height: 550)); expectFalse(model.isReady)
        // A second press without Option must confirm, not move the preview or start over.
        model.press(b); expectFalse(model.isReady); model.release(b)
        expectTrue(model.isReady); expectEqual(model.anchor, nil)
    }
    func testDefaultTwoPointAndReverseCorners() {
        var model = SelectionModel(size: size, method: .twoPoint)
        model.press(b); model.release(b); model.hover(a)
        model.press(a); model.release(a)
        expectTrue(model.isReady); expectEqual(model.rect, CGRect(x: 40, y: 50, width: 760, height: 550))
    }
    func testAllCornerDirections() {
        for corner in [CGPoint(x: 20, y: 20), CGPoint(x: 900, y: 20), CGPoint(x: 20, y: 600), CGPoint(x: 900, y: 600)] {
            var model = SelectionModel(size: size, method: .twoPoint)
            let center = CGPoint(x: 500, y: 350)
            model.press(center); model.release(center); model.press(corner); model.release(corner)
            expectTrue(model.isReady); expectEqual(model.rect, Geometry.rect(from: center, to: corner))
        }
    }
    func testClickJitterDoesNotComplete() {
        var model = SelectionModel(size: size, method: .twoPoint)
        model.press(a); model.drag(CGPoint(x: 42, y: 51)); model.release(CGPoint(x: 42, y: 51))
        expectEqual(model.anchor, a); expectFalse(model.isReady)
    }
    func testDirectDragStillWorksInBothModes() {
        for method in SelectionMethod.allCases {
            var model = SelectionModel(size: size, method: method)
            model.press(a); model.drag(b); model.release(b)
            expectTrue(model.isReady); expectEqual(model.anchor, nil)
            expectEqual(model.rect, Geometry.rect(from: a, to: b))
        }
    }
    func testDeleteKeepsTemporaryMode() {
        var model = SelectionModel(size: size)
        model.press(a, option: true); model.release(a); model.hover(b); model.reset()
        expectEqual(model.rect, .zero); expectEqual(model.anchor, nil); expectEqual(model.method, .twoPoint)
        model.press(b); model.release(b); expectEqual(model.anchor, b); expectFalse(model.isReady)
    }
    func testInvalidSecondPointCanBeRetried() {
        var model = SelectionModel(size: size, method: .twoPoint)
        model.press(a); model.release(a); model.press(a); model.release(a)
        expectFalse(model.isReady); expectEqual(model.anchor, a)
        model.press(CGPoint(x: a.x, y: 600)); model.release(CGPoint(x: a.x, y: 600))
        expectFalse(model.isReady); expectEqual(model.anchor, a)
        model.press(b); model.release(b); expectTrue(model.isReady)
    }
    func testFinalSelectionCanMoveAndResize() {
        var model = SelectionModel(size: size, method: .twoPoint)
        model.press(a); model.release(a); model.press(b); model.release(b)
        model.press(CGPoint(x: 100, y: 100)); model.drag(CGPoint(x: 120, y: 120)); model.release(CGPoint(x: 120, y: 120))
        expectEqual(model.rect, CGRect(x: 60, y: 70, width: 760, height: 550))
        model.press(CGPoint(x: 820, y: 620)); model.drag(CGPoint(x: 900, y: 650)); model.release(CGPoint(x: 900, y: 650))
        expectEqual(model.rect, CGRect(x: 60, y: 70, width: 840, height: 580)); expectTrue(model.isReady)
        model.hover(CGPoint(x: 400, y: 400)); expectEqual(model.rect, CGRect(x: 60, y: 70, width: 840, height: 580))
    }
    func testPreviewStaysWithinDisplay() {
        var model = SelectionModel(size: size, method: .twoPoint)
        model.press(a); model.release(a); model.hover(CGPoint(x: 5000, y: -100))
        expectEqual(model.rect, CGRect(x: 40, y: 0, width: 960, height: 50))
        model.press(CGPoint(x: 5000, y: -100)); model.release(CGPoint(x: 5000, y: -100)); expectTrue(model.isReady)
    }
    func testMagnifierEdgesAndRetinaMapping() {
        let pixels = CGSize(width: 2000, height: 1400)
        expectEqual(MagnifierGeometry.sample(at: CGPoint(x: 100, y: 100), viewSize: size, pixels: pixels), CGRect(x: 192, y: 192, width: 17, height: 17))
        expectEqual(MagnifierGeometry.sample(at: .zero, viewSize: size, pixels: pixels), CGRect(x: 0, y: 0, width: 17, height: 17))
        expectEqual(MagnifierGeometry.sample(at: CGPoint(x: 1000, y: 700), viewSize: size, pixels: pixels), CGRect(x: 1983, y: 1383, width: 17, height: 17))
        expectEqual(MagnifierGeometry.sample(at: .zero, viewSize: size, pixels: CGSize(width: 5, height: 6)), CGRect(x: 0, y: 0, width: 5, height: 6))
    }
    func testPreferenceRoundTripAndInvalidValueFallback() {
        let name = "ishot-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        expectEqual(SelectionMethod.saved(in: defaults), .drag)
        SelectionMethod.twoPoint.save(in: defaults); expectEqual(SelectionMethod.saved(in: defaults), .twoPoint)
        defaults.set("invalid", forKey: SelectionMethod.preferenceKey); expectEqual(SelectionMethod.saved(in: defaults), .drag)
    }
}
