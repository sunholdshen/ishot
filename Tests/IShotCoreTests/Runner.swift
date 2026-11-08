import AppKit

private var failures = 0
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
}
func expectEqual(_ actual: CGFloat, _ expected: CGFloat, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    if abs(actual - expected) > accuracy { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected) ± \(accuracy)") }
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectEqual(value, true, file: file, line: line) }
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectEqual(value, false, file: file, line: line) }
struct MissingValue: Error {}
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw MissingValue() }; return value }

@main struct Runner {
    static func main() {
        let geometry = GeometryTests(), images = ImageDocumentTests(), selection = SelectionTests()
        let checks: [(String, () throws -> Void)] = [
            ("reverse drag", geometry.testReverseDrag),
            ("Retina mapping", geometry.testRetinaSelection),
            ("clip and outward rounding", geometry.testSelectionClampsAndRoundsOutward),
            ("outside selection", geometry.testOutsideSelectionIsEmpty),
            ("zero viewport", geometry.testInvalidSizeIsEmpty),
            ("aspect ratio", geometry.testFitPreservesAspectRatio),
            ("no unwanted upscale", geometry.testFitDoesNotUpscale),
            ("movement boundaries", geometry.testMovementStopsAtEdges),
            ("fractional display scale", geometry.testMixedDensityMapping),
            ("render orientation and resolution", images.testRenderingPreservesOrientationAndResolution),
            ("irreversible opaque cover export", images.testOpaqueCoverReplacesSourcePixels),
            ("undo and redo", images.testUndoRedo),
            ("new edits invalidate redo", images.testNewEditInvalidatesRedo),
            ("crop origin and undo", images.testCropUsesTopLeftCoordinates),
            ("crop flatten and restore", images.testCropFlattensMarksAndUndoRestoresEditableMarks),
            ("invalid crop", images.testInvalidCropLeavesDocumentUntouched),
            ("PNG roundtrip", images.testPNGCanBeDecodedWithoutLosingPixels),
            ("bounded history", images.testHistoryIsBounded),
            ("all annotation tools", images.testAllDrawingToolsRender),
            ("Option first click latches two-point mode", selection.testOptionLatchesUntilSecondClick),
            ("default two-point reverse corners", selection.testDefaultTwoPointAndReverseCorners),
            ("all diagonal directions", selection.testAllCornerDirections),
            ("click jitter keeps first anchor", selection.testClickJitterDoesNotComplete),
            ("drag compatibility in both modes", selection.testDirectDragStillWorksInBothModes),
            ("Delete preserves temporary mode", selection.testDeleteKeepsTemporaryMode),
            ("retry invalid second point", selection.testInvalidSecondPointCanBeRetried),
            ("move and resize finalized selection", selection.testFinalSelectionCanMoveAndResize),
            ("selection stays within its display", selection.testPreviewStaysWithinDisplay),
            ("magnifier Retina and edge sampling", selection.testMagnifierEdgesAndRetinaMapping),
            ("selection preference persistence", selection.testPreferenceRoundTripAndInvalidValueFallback)
        ]
        for (name, check) in checks {
            let before = failures
            do { try check() } catch { failures += 1; print("FAIL \(name): \(error)") }
            if failures == before { print("PASS \(name)") }
        }
        print("\(checks.count) checks; \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
