import Foundation

public enum SelectionMethod: String, CaseIterable {
    case drag, twoPoint
    public static let preferenceKey = "selectionMethod"
    public static func saved(in defaults: UserDefaults = .standard) -> SelectionMethod {
        SelectionMethod(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .drag
    }
    public func save(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}

/// Capture-local state. A first click latches two-point selection until the session ends;
/// neither releasing Option nor pausing pointer movement completes the rectangle.
public struct SelectionModel {
    private enum Gesture {
        case none, first(CGPoint, allowDrag: Bool), second
        case drag(CGPoint), move(CGPoint, CGRect), resize(CGPoint)
    }
    public private(set) var method: SelectionMethod
    public private(set) var rect: CGRect = .zero
    public private(set) var anchor: CGPoint?
    private var gesture: Gesture = .none
    public let bounds: CGRect
    public var isInteracting: Bool { if case .none = gesture { return false }; return true }
    public var isReady: Bool { anchor == nil && !isInteracting && rect.width >= 2 && rect.height >= 2 }
    public var corners: [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }
    public init(size: CGSize, method: SelectionMethod = .drag) {
        self.bounds = CGRect(origin: .zero, size: size); self.method = method
    }
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(bounds.minX, point.x), bounds.maxX), y: min(max(bounds.minY, point.y), bounds.maxY))
    }
    public mutating func press(_ point: CGPoint, option: Bool = false) {
        let p = clamped(point)
        if let anchor {
            gesture = .second; rect = Geometry.rect(from: anchor, to: p); return
        }
        if isReady && !option {
            if let index = corners.firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) <= 12 }) {
                gesture = .resize(corners[3 - index]); return
            }
            if rect.contains(p) { gesture = .move(p, rect); return }
        }
        rect = .zero
        if option { method = .twoPoint }
        if method == .twoPoint {
            anchor = p; gesture = .first(p, allowDrag: !option)
        } else { gesture = .drag(p) }
    }
    public mutating func hover(_ point: CGPoint) {
        guard !isInteracting, let anchor else { return }
        rect = Geometry.rect(from: anchor, to: clamped(point))
    }
    public mutating func drag(_ point: CGPoint) {
        let p = clamped(point)
        switch gesture {
        case let .first(start, allowDrag):
            // Keep normal dragging available even when two-point is the default.
            // A small click jitter must not silently turn the first click into a drag.
            if allowDrag && hypot(p.x - start.x, p.y - start.y) > 4 {
                anchor = nil; gesture = .drag(start); rect = Geometry.rect(from: start, to: p)
            }
        case .second:
            if let anchor { rect = Geometry.rect(from: anchor, to: p) }
        case let .drag(start): rect = Geometry.rect(from: start, to: p)
        case let .move(start, original):
            rect = Geometry.moved(original, by: CGPoint(x: p.x - start.x, y: p.y - start.y), within: bounds)
        case let .resize(opposite): rect = Geometry.rect(from: opposite, to: p)
        case .none: break
        }
    }
    public mutating func release(_ point: CGPoint) {
        // The first point is the down location. Mouse-up must not become the second point.
        if case .first = gesture { gesture = .none; return }
        drag(point)
        if case .second = gesture, rect.width >= 2, rect.height >= 2 { anchor = nil }
        gesture = .none
        if anchor == nil && (rect.width < 2 || rect.height < 2) { rect = .zero }
    }
    public mutating func reset() { rect = .zero; anchor = nil; gesture = .none }
}

public enum MagnifierGeometry {
    /// An odd-sized source patch, clamped in bitmap pixels (not display points).
    public static func sample(at point: CGPoint, viewSize: CGSize, pixels: CGSize, side: CGFloat = 17) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0, pixels.width > 0, pixels.height > 0 else { return .zero }
        let width = min(side, pixels.width), height = min(side, pixels.height)
        let x = min(max(0, floor(point.x * pixels.width / viewSize.width)), pixels.width - 1)
        let y = min(max(0, floor(point.y * pixels.height / viewSize.height)), pixels.height - 1)
        return CGRect(x: min(max(0, x - floor(width / 2)), pixels.width - width),
                      y: min(max(0, y - floor(height / 2)), pixels.height - height), width: width, height: height)
    }
}
