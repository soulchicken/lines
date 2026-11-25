import AppKit

protocol InkMark {
    var bounds: CGRect { get }
    func draw(in context: CGContext, dirtyRect: CGRect)
}

/// An ink mark in progress, either a smoothed path or a rectangle outline.
final class InkStroke: InkMark {
    private let color: PenColor
    private let rectangleOrigin: CGPoint?
    private(set) var bounds: CGRect
    private var lastSample: CGPoint
    private var anchor: CGPoint
    private var startControl: CGPoint
    private var path = CGMutablePath()
    private var segments = 0
    private var completed: [(path: CGPath, bounds: CGRect)] = []

    // Includes the white outline and antialiasing at the edge.
    private static let margin: CGFloat = 4

    init(start: CGPoint, color: PenColor, isRectangle: Bool = false) {
        self.color = color
        rectangleOrigin = isRectangle ? start : nil
        bounds = CGRect(origin: start, size: .zero).insetBy(dx: -Self.margin, dy: -Self.margin)
        lastSample = start
        anchor = start
        startControl = start
        path.move(to: start)
    }

    private func rectangle(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func extent(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        rectangle(from: a, to: b).insetBy(dx: -Self.margin, dy: -Self.margin)
    }

    var hasInk: Bool {
        guard let rectangleOrigin else { return true }
        return !rectangle(from: rectangleOrigin, to: lastSample).isEmpty
    }

    var tipBounds: CGRect { extent(anchor, lastSample).union(extent(anchor, startControl)) }

    func append(_ point: CGPoint) -> CGRect? {
        if let rectangleOrigin {
            guard point != lastSample else { return nil }
            let dirty = bounds
            lastSample = point
            bounds = extent(rectangleOrigin, point)
            return dirty.union(bounds)
        }
        let dx = point.x - lastSample.x
        let dy = point.y - lastSample.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return nil }
        var dirty = tipBounds.union(extent(lastSample, point))
        let previousLength = hypot(lastSample.x - anchor.x, lastSample.y - anchor.y)
        var nextControl = lastSample
        if previousLength > 0 {
            let px = (lastSample.x - anchor.x) / previousLength
            let py = (lastSample.y - anchor.y) / previousLength
            let nx = dx / distance
            let ny = dy / distance
            // Interpolate through the sample. Ease bends, but stop rounding
            // at sharp turns or reversals. Limit handles on uneven input.
            let strength = max(0, px * nx + py * ny)
            let handle = min(previousLength, distance) * strength / 3
            let length = hypot(px + nx, py + ny)
            let tx = length > 0 ? (px + nx) * handle / length : 0
            let ty = length > 0 ? (py + ny) * handle / length : 0
            let endControl = CGPoint(x: lastSample.x - tx, y: lastSample.y - ty)
            nextControl = CGPoint(x: lastSample.x + tx, y: lastSample.y + ty)
            path.addCurve(to: lastSample, control1: startControl, control2: endControl)
            dirty = dirty.union(extent(endControl, nextControl))
            segments += 1
        } else {
            nextControl = CGPoint(x: lastSample.x + dx / 3, y: lastSample.y + dy / 3)
        }
        bounds = bounds.union(dirty)
        anchor = lastSample
        startControl = nextControl
        lastSample = point

        // Cache bounds for finished pieces so dragging a long stroke only
        // replays pieces that intersect the area being repainted.
        if segments == 64 {
            completed.append((path, path.boundingBox.insetBy(dx: -Self.margin, dy: -Self.margin)))
            path = CGMutablePath()
            path.move(to: anchor)
            segments = 0
        }
        return dirty
    }

    func draw(in context: CGContext, dirtyRect: CGRect) {
        guard bounds.intersects(dirtyRect) else { return }
        if let rectangleOrigin {
            let rect = rectangle(from: rectangleOrigin, to: lastSample)
            if !rect.isEmpty { stroke(CGPath(rect: rect, transform: nil), in: context) }
            return
        }
        let visible = CGMutablePath()
        for piece in completed where piece.bounds.intersects(dirtyRect) {
            visible.addPath(piece.path)
        }
        if segments > 0 && path.boundingBox.insetBy(dx: -Self.margin, dy: -Self.margin).intersects(dirtyRect) {
            visible.addPath(path)
        }
        if tipBounds.intersects(dirtyRect) {
            if anchor == lastSample && completed.isEmpty && segments == 0 {
                context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                context.fillEllipse(in: CGRect(origin: lastSample, size: .zero).insetBy(dx: -3, dy: -3))
                context.setFillColor(color.ink.cgColor)
                context.fillEllipse(in: CGRect(origin: lastSample, size: .zero).insetBy(dx: -2, dy: -2))
                return
            }
            visible.move(to: anchor)
            visible.addQuadCurve(to: lastSample, control: startControl)
        }
        guard !visible.isEmpty else { return }
        stroke(visible, in: context)
    }

    private func stroke(_ path: CGPath, in context: CGContext) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(6)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.addPath(path)
        context.strokePath()
        context.setLineWidth(4)
        context.setStrokeColor(color.ink.cgColor)
        context.addPath(path)
        context.strokePath()
    }
}
