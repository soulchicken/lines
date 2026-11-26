import AppKit

/// Short-lived presentation marks, separate from the canvas's editable ink.
final class LaserPointerView: NSView {
    enum Duration: TimeInterval, CaseIterable {
        case short = 0.7
        case standard = 1.4
        case twoSeconds = 2
        case threeSeconds = 3
        case fiveSeconds = 5
        case tenSeconds = 10
        case fifteenSeconds = 15
        case twentySeconds = 20
    }

    private struct Sample {
        let point: CGPoint
        let distance: CGFloat
    }

    private struct FadeSection {
        let path: CGPath
        let durationFraction: Double
    }

    private struct FadingTrail {
        let sections: [FadeSection]
        let bounds: CGRect
        let alpha: CGFloat
        let releasedAt: TimeInterval
    }

    private static let trailLayers: [(width: CGFloat, opacity: CGFloat)] = [(9, 0.05), (5.5, 0.12), (2.7, 0.68)]

    private var samples: [Sample] = []
    private var fadingTrails: [FadingTrail] = []
    private var fadeTimer: Timer?
    private var highlightTimer: Timer?
    private var liveBounds = CGRect.null
    private var isPressed = false
    private var lastReleaseAt: TimeInterval?
    private var isHighlighted = false {
        didSet {
            if isHighlighted != oldValue { onCursorChange?() }
        }
    }
    private var tailDistance: CGFloat = 0
    var onCursorChange: (() -> Void)?
    var duration = Duration(rawValue: UserDefaults.standard.double(forKey: "laserDuration")) ?? .standard {
        didSet {
            UserDefaults.standard.set(duration.rawValue, forKey: "laserDuration")
            scheduleHighlightEnd()
        }
    }

    private var maximumTrailLength: CGFloat {
        max(2400, hypot(bounds.width, bounds.height) * 1.25)
    }
    var color = PenColor(rawValue: UserDefaults.standard.integer(forKey: "laserColor")) ?? .red {
        didSet {
            normalCursor = Self.makePointerCursor(for: color, highlighted: false)
            brightCursor = Self.makePointerCursor(for: color, highlighted: true)
            UserDefaults.standard.set(color.rawValue, forKey: "laserColor")
            onCursorChange?()
            if !liveBounds.isNull { setNeedsDisplay(liveBounds) }
            for trail in fadingTrails { setNeedsDisplay(trail.bounds) }
        }
    }
    private lazy var normalCursor = Self.makePointerCursor(for: color, highlighted: false)
    private lazy var brightCursor = Self.makePointerCursor(for: color, highlighted: true)
    var pointerCursor: NSCursor { isHighlighted ? brightCursor : normalCursor }

    private static func makePointerCursor(for color: PenColor, highlighted: Bool) -> NSCursor {
        let size = NSSize(width: 32, height: 32)
        let ink = color.ink
        let intensity = highlighted ? 1.0 : 0.62
        let stops = [0.62, 0.32, 0.10, 0.0].map { ink.withAlphaComponent($0 * intensity).cgColor }
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: stops as CFArray, locations: [0, 0.32, 0.67, 1])
        let image = NSImage(size: size, flipped: false) { rect in
            let point = CGPoint(x: rect.midX, y: rect.midY)
            if let glow, let context = NSGraphicsContext.current?.cgContext {
                context.drawRadialGradient(glow, startCenter: point, startRadius: 0, endCenter: point,
                                           endRadius: highlighted ? 15 : 11, options: [])
            }
            let center = CGRect(origin: point, size: .zero)
            let radius: CGFloat = highlighted ? 4.6 : 3.7
            ink.setFill()
            NSBezierPath(ovalIn: center.insetBy(dx: -radius, dy: -radius)).fill()
            NSColor.white.setFill()
            let coreRadius: CGFloat = highlighted ? 1.8 : 1.5
            NSBezierPath(ovalIn: center.insetBy(dx: -coreRadius, dy: -coreRadius)).fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func press(at position: CGPoint) {
        clearLiveTrail()
        highlightTimer?.invalidate()
        highlightTimer = nil
        lastReleaseAt = nil
        isPressed = true
        isHighlighted = true
        record(position)
    }

    func drag(to position: CGPoint) {
        guard isPressed else { return }
        record(position)
    }

    func release(at position: CGPoint) {
        guard isPressed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        record(position)
        isPressed = false
        lastReleaseAt = now
        let sections = makeFadeSections()
        if !sections.isEmpty {
            fadingTrails.append(FadingTrail(sections: sections, bounds: liveBounds, alpha: liveAlpha, releasedAt: now))
            startFadeTimer()
        }
        clearLiveTrail()
        scheduleHighlightEnd()
    }

    private func record(_ position: CGPoint) {
        guard bounds.contains(position) else { clearLiveTrail(); return }

        if let last = samples.last {
            if position != last.point {
                let step = hypot(position.x - last.point.x, position.y - last.point.y)
                if samples.count >= 2 && last.distance - samples[samples.count - 2].distance < 2 {
                    samples.removeLast()
                }
                samples.append(Sample(point: position, distance: last.distance + step))
            }
        } else {
            samples.append(Sample(point: position, distance: 0))
        }
        trimLiveTrail()
        updateTrailDisplay()
    }

    private func startFadeTimer() {
        guard fadeTimer == nil else { return }
        let ticker = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let cutoff = ProcessInfo.processInfo.systemUptime - self.duration.rawValue
            self.fadingTrails.removeAll { trail in
                self.setNeedsDisplay(trail.bounds)
                return trail.releasedAt <= cutoff
            }
            if self.fadingTrails.isEmpty {
                timer.invalidate()
                self.fadeTimer = nil
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        fadeTimer = ticker
    }

    private func scheduleHighlightEnd() {
        highlightTimer?.invalidate()
        highlightTimer = nil
        guard let lastReleaseAt, isHighlighted else { return }
        let remaining = duration.rawValue - (ProcessInfo.processInfo.systemUptime - lastReleaseAt)
        if remaining <= 0 {
            isHighlighted = false
            return
        }
        let timeout = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            self?.isHighlighted = false
            self?.highlightTimer = nil
        }
        RunLoop.main.add(timeout, forMode: .common)
        highlightTimer = timeout
    }

    private func trimLiveTrail() {
        guard let head = samples.last else { return }
        tailDistance = max(tailDistance, head.distance - maximumTrailLength)
        let first = samples.firstIndex { $0.distance > tailDistance }
            .map { max(0, $0 - 1) } ?? samples.count - 1
        samples.removeFirst(first)
    }

    private func updateTrailDisplay() {
        var next = CGRect.null
        for sample in samples {
            next = next.union(CGRect(origin: sample.point, size: .zero).insetBy(dx: -6, dy: -6))
        }
        setNeedsDisplay(liveBounds.union(next))
        liveBounds = next
    }

    func clear() {
        isPressed = false
        lastReleaseAt = nil
        highlightTimer?.invalidate()
        highlightTimer = nil
        isHighlighted = false
        fadeTimer?.invalidate()
        fadeTimer = nil
        for trail in fadingTrails { setNeedsDisplay(trail.bounds) }
        fadingTrails.removeAll()
        clearLiveTrail()
    }

    private func clearLiveTrail() {
        samples.removeAll(keepingCapacity: true)
        tailDistance = 0
        if !liveBounds.isNull { setNeedsDisplay(liveBounds) }
        liveBounds = .null
    }

    private var liveAlpha: CGFloat {
        guard let head = samples.last else { return 0 }
        return min(1, (head.distance - tailDistance) / 12)
    }

    private func livePath() -> CGPath? {
        guard samples.count > 1, let head = samples.last else { return nil }
        let first = samples[0]
        let next = samples[1]
        let span = next.distance - first.distance
        let fraction = min(1, max(0, (tailDistance - first.distance) / span))
        let start = CGPoint(x: first.point.x + (next.point.x - first.point.x) * fraction,
                            y: first.point.y + (next.point.y - first.point.y) * fraction)
        let path = CGMutablePath()
        path.move(to: start)
        for index in 1..<(samples.count - 1) {
            let point = samples[index].point
            let following = samples[index + 1].point
            let midpoint = CGPoint(x: (point.x + following.x) / 2, y: (point.y + following.y) / 2)
            path.addQuadCurve(to: midpoint, control: point)
        }
        path.addLine(to: head.point)
        return path
    }

    private func makeFadeSections() -> [FadeSection] {
        guard let path = livePath() else { return [] }
        var points: [Sample] = []
        path.flattened(threshold: 0.18).applyWithBlock { element in
            guard element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint else { return }
            let point = element.pointee.points[0]
            if let last = points.last {
                let step = hypot(point.x - last.point.x, point.y - last.point.y)
                if step > 0 { points.append(Sample(point: point, distance: last.distance + step)) }
            } else {
                points.append(Sample(point: point, distance: 0))
            }
        }
        guard let end = points.last?.distance, end > 0 else { return [] }

        // Cache overlapping suffixes at equal distances. Opacity can then
        // vary along the curve without redrawing its geometry or leaving joints.
        let count = 20
        let firstSectionFraction = 0.2875
        var next = 1
        return (0..<count).map { index in
            let cutoff = end * CGFloat(index) / CGFloat(count)
            while points[next].distance <= cutoff { next += 1 }
            let from = points[next - 1]
            let to = points[next]
            let fraction = (cutoff - from.distance) / (to.distance - from.distance)
            let section = CGMutablePath()
            section.move(to: CGPoint(x: from.point.x + (to.point.x - from.point.x) * fraction,
                                     y: from.point.y + (to.point.y - from.point.y) * fraction))
            for point in points[next...] { section.addLine(to: point.point) }
            let durationFraction = firstSectionFraction + (1 - firstSectionFraction) * Double(index) / Double(count - 1)
            return FadeSection(path: section, durationFraction: durationFraction)
        }
    }

    private func draw(_ trail: FadingTrail, in context: CGContext, ink: NSColor, at now: TimeInterval) {
        let elapsedFraction = (now - trail.releasedAt) / duration.rawValue
        for layer in Self.trailLayers {
            context.setLineWidth(layer.width)
            var previous: CGFloat = 0
            for section in trail.sections {
                let t = min(1, max(0, elapsedFraction / section.durationFraction))
                let opacity = layer.opacity * trail.alpha * CGFloat(1 - t * t * (3 - 2 * t))
                guard opacity - previous >= 1.0 / 255 else { continue }
                context.setStrokeColor(ink.withAlphaComponent((opacity - previous) / (1 - previous)).cgColor)
                context.addPath(section.path)
                context.strokePath()
                previous = opacity
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let now = ProcessInfo.processInfo.systemUptime
        let ink = color.ink
        for trail in fadingTrails where dirtyRect.intersects(trail.bounds) {
            draw(trail, in: ctx, ink: ink, at: now)
        }
        if dirtyRect.intersects(liveBounds), let path = livePath() {
            let alpha = liveAlpha
            for layer in Self.trailLayers {
                ctx.setLineWidth(layer.width)
                ctx.setStrokeColor(ink.withAlphaComponent(layer.opacity * alpha).cgColor)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}
