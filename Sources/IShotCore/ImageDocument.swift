import AppKit

public enum MarkTool: String, CaseIterable {
    case rectangle = "矩形", ellipse = "椭圆", arrow = "箭头", pen = "画笔", text = "文字", cover = "遮挡", crop = "裁剪"
    public var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .cover: return "rectangle.fill"
        case .crop: return "crop"
        }
    }
}

public struct Annotation {
    public var tool: MarkTool
    public var points: [CGPoint]
    public var color: NSColor
    public var width: CGFloat
    public var text: String
    public init(tool: MarkTool, points: [CGPoint], color: NSColor = .systemRed, width: CGFloat = 4, text: String = "") {
        self.tool = tool; self.points = points; self.color = color; self.width = width; self.text = text
    }

    public func draw() {
        guard let first = points.first, let last = points.last else { return }
        let rect = Geometry.rect(from: first, to: last)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        switch tool {
        case .rectangle: path.appendRect(rect)
        case .ellipse: path.appendOval(in: rect)
        case .pen:
            path.move(to: first)
            if points.count == 1 { path.line(to: CGPoint(x: first.x + 0.1, y: first.y)) }
            else { points.dropFirst().forEach { path.line(to: $0) } }
        case .arrow:
            path.move(to: first); path.line(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x)
            let length = max(12, width * 4)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: last)
                path.line(to: CGPoint(x: last.x - length * cos(angle + offset), y: last.y - length * sin(angle + offset)))
            }
        case .text:
            (text as NSString).draw(at: first, withAttributes: [.font: NSFont.systemFont(ofSize: max(18, width * 6), weight: .semibold), .foregroundColor: color])
            return
        case .cover:
            // A cover is always fully opaque; exported pixels cannot reveal the original.
            color.withAlphaComponent(1).setFill(); rect.fill(); return
        case .crop: return
        }
        path.stroke()
    }
}

public final class ImageDocument {
    private struct State { let image: CGImage; let marks: [Annotation] }
    public private(set) var image: CGImage
    public private(set) var marks: [Annotation] = []
    private var past: [State] = []
    private var future: [State] = []
    public var size: CGSize { CGSize(width: image.width, height: image.height) }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public init(image: CGImage) { self.image = image }
    private func snapshot() {
        past.append(State(image: image, marks: marks)); future.removeAll()
        if past.count > 50 { past.removeFirst() }
    }
    public func add(_ mark: Annotation) { snapshot(); marks.append(mark) }
    public func undo() {
        guard let state = past.popLast() else { return }
        future.append(State(image: image, marks: marks)); image = state.image; marks = state.marks
    }
    public func redo() {
        guard let state = future.popLast() else { return }
        past.append(State(image: image, marks: marks)); image = state.image; marks = state.marks
    }
    public func crop(to rect: CGRect) {
        let clipped = rect.integral.intersection(CGRect(origin: .zero, size: size))
        guard clipped.width >= 2, clipped.height >= 2, let rendered = renderedImage(), let cropped = rendered.cropping(to: clipped) else { return }
        snapshot(); image = cropped; marks = []
    }
    public func draw(in context: CGContext, draft: Annotation? = nil) {
        // The caller supplies a top-left coordinate system.
        context.saveGState()
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        marks.forEach { $0.draw() }; draft?.draw()
        NSGraphicsContext.restoreGraphicsState()
    }
    public func renderedImage() -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        draw(in: context)
        return context.makeImage()
    }
    public func pngData() -> Data? {
        guard let image = renderedImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
