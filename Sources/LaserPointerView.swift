import AppKit

/// Short-lived presentation marks, separate from the canvas's editable ink.
final class LaserPointerView: NSView {
    private struct Sample {
        let point: CGPoint
        let time: TimeInterval
    }

    private var samples: [Sample] = []
    private var timer: Timer?
    private var paintedBounds = CGRect.null
    private let trailLifetime = 0.22
    private let dotLifetime = 0.70
    var color = PenColor(rawValue: UserDefaults.standard.integer(forKey: "laserColor")) ?? .red {
        didSet {
            UserDefaults.standard.set(color.rawValue, forKey: "laserColor")
            if !paintedBounds.isNull { setNeedsDisplay(paintedBounds) }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func point(at position: CGPoint) {
        guard bounds.contains(position) else { clear(); return }
        let now = ProcessInfo.processInfo.systemUptime
        // Avoid allocating one sample for every raw mouse event on fast devices.
        if samples.count >= 2 && now - samples[samples.count - 2].time < 1.0 / 90 {
            samples.removeLast()
        }
        samples.append(Sample(point: position, time: now))
        refresh(at: now)
        if timer == nil {
            let ticker = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.refresh(at: ProcessInfo.processInfo.systemUptime)
            }
            RunLoop.main.add(ticker, forMode: .common)
            timer = ticker
        }
    }

    private func refresh(at now: TimeInterval) {
        guard let head = samples.last, now - head.time < dotLifetime else { clear(); return }
        // Keep the head visible briefly after the shorter trail expires.
        let first = samples.firstIndex { now - $0.time < trailLifetime } ?? samples.count - 1
        samples.removeFirst(first)
        var next = CGRect.null
        for sample in samples {
            next = next.union(CGRect(origin: sample.point, size: .zero).insetBy(dx: -10, dy: -10))
        }
        setNeedsDisplay(paintedBounds.union(next))
        paintedBounds = next
    }

    func clear() {
        timer?.invalidate()
        timer = nil
        samples.removeAll(keepingCapacity: true)
        if !paintedBounds.isNull { setNeedsDisplay(paintedBounds) }
        paintedBounds = .null
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let head = samples.last, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let ink = color.ink
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineWidth(3)
        for (from, to) in zip(samples, samples.dropFirst()) {
            let alpha = max(0, 1 - (now - from.time) / trailLifetime)
            ctx.setStrokeColor(ink.withAlphaComponent(0.65 * alpha).cgColor)
            ctx.move(to: from.point)
            ctx.addLine(to: to.point)
            ctx.strokePath()
        }
        ctx.setAlpha(min(1, max(0, (dotLifetime - (now - head.time)) / 0.35)))
        let center = CGRect(origin: head.point, size: .zero)
        ctx.setFillColor(ink.withAlphaComponent(0.22).cgColor)
        ctx.fillEllipse(in: center.insetBy(dx: -9, dy: -9))
        ctx.setFillColor(ink.cgColor)
        ctx.fillEllipse(in: center.insetBy(dx: -5, dy: -5))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: center.insetBy(dx: -2, dy: -2))
        ctx.restoreGState()
    }
}
