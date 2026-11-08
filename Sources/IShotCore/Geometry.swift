import Foundation

public enum Geometry {
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// View coordinates and bitmap coordinates both start at the top left.
    public static func pixelRect(_ selection: CGRect, viewSize: CGSize, pixels: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: viewSize))
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        return CGRect(x: clipped.minX * pixels.width / viewSize.width,
                      y: clipped.minY * pixels.height / viewSize.height,
                      width: clipped.width * pixels.width / viewSize.width,
                      height: clipped.height * pixels.height / viewSize.height)
            .integral.intersection(CGRect(origin: .zero, size: pixels))
    }

    public static func fittedSize(_ size: CGSize, within limit: CGSize, allowUpscale: Bool = false) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let scale = min(limit.width / size.width, limit.height / size.height, allowUpscale ? .greatestFiniteMagnitude : 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    public static func moved(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: min(max(bounds.minX, rect.minX + delta.x), bounds.maxX - rect.width),
               y: min(max(bounds.minY, rect.minY + delta.y), bounds.maxY - rect.height),
               width: rect.width, height: rect.height)
    }
}
