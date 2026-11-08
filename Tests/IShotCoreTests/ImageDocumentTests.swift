import AppKit
import IShotCore

final class ImageDocumentTests {
    // Top half red, bottom half blue, independent of drawing coordinate transforms.
    private func image() -> CGImage {
        var data = [UInt8](repeating: 255, count: 80 * 60 * 4)
        for y in 0..<60 { for x in 0..<80 {
            let i = (y * 80 + x) * 4
            data[i] = y < 30 ? 255 : 0; data[i + 1] = 0; data[i + 2] = y < 30 ? 0 : 255
        } }
        return CGImage(width: 80, height: 60, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 80 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    private func color(_ image: CGImage, x: Int, y: Int) -> NSColor {
        // Read actual sRGB pixels. colorAt() labels numeric components as calibrated
        // RGB on some systems; converting that NSColor would apply a second transform.
        let bitmap = NSBitmapImageRep(cgImage: image)
        var pixel = [Int](repeating: 0, count: 4)
        bitmap.getPixel(&pixel, atX: x, y: y)
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: CGFloat(pixel[3]) / 255)
    }
    func testRenderingPreservesOrientationAndResolution() throws {
        let output = try unwrap(ImageDocument(image: image()).renderedImage())
        expectEqual(output.width, 80); expectEqual(output.height, 60)
        expectEqual(color(output, x: 10, y: 10).redComponent, 1, accuracy: 0.01)
        expectEqual(color(output, x: 10, y: 50).blueComponent, 1, accuracy: 0.01)
    }
    func testOpaqueCoverReplacesSourcePixels() throws {
        let document = ImageDocument(image: image())
        document.add(Annotation(tool: .cover, points: [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 25)], color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 0.2)))
        let output = try unwrap(document.renderedImage())
        let inside = color(output, x: 10, y: 10)
        expectEqual(inside.greenComponent, 1, accuracy: 0.01); expectEqual(inside.redComponent, 0, accuracy: 0.01); expectEqual(inside.alphaComponent, 1, accuracy: 0.01)
        expectEqual(color(output, x: 40, y: 10).redComponent, 1, accuracy: 0.01)
        expectEqual(color(output, x: 10, y: 50).blueComponent, 1, accuracy: 0.01)
    }
    func testUndoRedo() {
        let document = ImageDocument(image: image())
        document.add(Annotation(tool: .rectangle, points: [.zero, CGPoint(x: 20, y: 20)]))
        expectTrue(document.canUndo); document.undo(); expectTrue(document.marks.isEmpty); expectTrue(document.canRedo)
        document.redo(); expectEqual(document.marks.count, 1)
    }
    func testNewEditInvalidatesRedo() {
        let document = ImageDocument(image: image())
        document.add(Annotation(tool: .pen, points: [.zero])); document.undo()
        document.add(Annotation(tool: .ellipse, points: [.zero, CGPoint(x: 20, y: 20)]))
        expectFalse(document.canRedo)
    }
    func testCropUsesTopLeftCoordinates() throws {
        let document = ImageDocument(image: image())
        document.crop(to: CGRect(x: 0, y: 0, width: 40, height: 20))
        expectEqual(document.size, CGSize(width: 40, height: 20))
        let output = try unwrap(document.renderedImage())
        expectEqual(color(output, x: 10, y: 10).redComponent, 1, accuracy: 0.01)
        document.undo(); expectEqual(document.size, CGSize(width: 80, height: 60))
        document.redo(); expectEqual(document.size, CGSize(width: 40, height: 20))
    }
    func testCropFlattensMarksAndUndoRestoresEditableMarks() throws {
        let document = ImageDocument(image: image())
        document.add(Annotation(tool: .cover, points: [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 25)], color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        document.crop(to: CGRect(x: 5, y: 5, width: 30, height: 30))
        expectTrue(document.marks.isEmpty)
        expectEqual(color(try unwrap(document.renderedImage()), x: 3, y: 3).greenComponent, 1, accuracy: 0.01)
        document.undo(); expectEqual(document.marks.count, 1); expectEqual(document.size, CGSize(width: 80, height: 60))
    }
    func testInvalidCropLeavesDocumentUntouched() {
        let document = ImageDocument(image: image()); document.crop(to: CGRect(x: 200, y: 200, width: 10, height: 10))
        expectFalse(document.canUndo); expectEqual(document.size, CGSize(width: 80, height: 60))
    }
    func testPNGCanBeDecodedWithoutLosingPixels() throws {
        let data = try unwrap(ImageDocument(image: image()).pngData())
        let decoded = try unwrap(NSBitmapImageRep(data: data))
        expectEqual(decoded.pixelsWide, 80); expectEqual(decoded.pixelsHigh, 60)
    }
    func testHistoryIsBounded() {
        let document = ImageDocument(image: image())
        for _ in 0..<60 { document.add(Annotation(tool: .pen, points: [.zero])) }
        for _ in 0..<55 { document.undo() }
        expectEqual(document.marks.count, 10); expectFalse(document.canUndo)
    }
    func testAllDrawingToolsRender() throws {
        let document = ImageDocument(image: image())
        for tool in MarkTool.allCases where tool != .crop {
            document.add(Annotation(tool: tool, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)], color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), width: 2, text: "A"))
        }
        let result = try unwrap(document.renderedImage())
        expectEqual(result.width, 80)
    }
}
