import Foundation
import IShotCore

final class GeometryTests {
    func testReverseDrag() {
        expectEqual(Geometry.rect(from: CGPoint(x: 90, y: 80), to: CGPoint(x: 10, y: 20)), CGRect(x: 10, y: 20, width: 80, height: 60))
    }
    func testRetinaSelection() {
        expectEqual(Geometry.pixelRect(CGRect(x: 10, y: 20, width: 100, height: 50), viewSize: CGSize(width: 800, height: 600), pixels: CGSize(width: 1600, height: 1200)), CGRect(x: 20, y: 40, width: 200, height: 100))
    }
    func testSelectionClampsAndRoundsOutward() {
        expectEqual(Geometry.pixelRect(CGRect(x: -5, y: 10.2, width: 35.3, height: 40.1), viewSize: CGSize(width: 100, height: 100), pixels: CGSize(width: 200, height: 200)), CGRect(x: 0, y: 20, width: 61, height: 81))
    }
    func testOutsideSelectionIsEmpty() {
        expectEqual(Geometry.pixelRect(CGRect(x: 200, y: 200, width: 30, height: 30), viewSize: CGSize(width: 100, height: 100), pixels: CGSize(width: 200, height: 200)), .zero)
    }
    func testInvalidSizeIsEmpty() {
        expectEqual(Geometry.pixelRect(CGRect(x: 0, y: 0, width: 20, height: 20), viewSize: .zero, pixels: CGSize(width: 200, height: 200)), .zero)
    }
    func testFitPreservesAspectRatio() {
        expectEqual(Geometry.fittedSize(CGSize(width: 2000, height: 1000), within: CGSize(width: 500, height: 400)), CGSize(width: 500, height: 250))
    }
    func testFitDoesNotUpscale() {
        expectEqual(Geometry.fittedSize(CGSize(width: 100, height: 50), within: CGSize(width: 500, height: 400)), CGSize(width: 100, height: 50))
    }
    func testMovementStopsAtEdges() {
        let moved = Geometry.moved(CGRect(x: 20, y: 20, width: 40, height: 30), by: CGPoint(x: 500, y: -500), within: CGRect(x: 0, y: 0, width: 100, height: 100))
        expectEqual(moved, CGRect(x: 60, y: 0, width: 40, height: 30))
    }
    func testMixedDensityMapping() {
        let rect = CGRect(x: 20, y: 20, width: 80, height: 50)
        expectEqual(Geometry.pixelRect(rect, viewSize: CGSize(width: 100, height: 100), pixels: CGSize(width: 150, height: 150)), CGRect(x: 30, y: 30, width: 120, height: 75))
    }
}
