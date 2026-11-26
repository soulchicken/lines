import AppKit

// xcrun swiftc -module-cache-path .build/modules Sources/{LaserPointerView,PenPalette}.swift \
//     Tests/LaserPointerViewTests.swift -o .build/lines-laser-tests
// .build/lines-laser-tests -laserDuration 1.4
@main
struct LaserPointerViewTests {
    static func main() {
        let view = LaserPointerView(frame: CGRect(x: 0, y: 0, width: 140, height: 100))
        let firstStart = CGPoint(x: 20, y: 25)
        let firstEnd = CGPoint(x: 110, y: 25)
        let secondStart = CGPoint(x: 20, y: 55)
        let secondEnd = CGPoint(x: 110, y: 55)

        view.press(at: firstStart)
        view.drag(to: firstEnd)
        view.release(at: firstEnd)
        precondition(alpha(in: render(view), y: 25) > 0, "Releasing should leave a visible trail")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.55))

        view.press(at: secondStart)
        precondition(alpha(in: render(view), y: 25) > 0, "A new press erased the first trail")
        view.drag(to: secondEnd)
        let duringDrag = render(view)
        precondition(alpha(in: duringDrag, y: 25) > 0 && alpha(in: duringDrag, y: 55) > 0,
                     "The fading trail and live trail should both be visible")
        view.release(at: secondEnd)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.95))

        let afterFirstFade = render(view)
        precondition(alpha(in: afterFirstFade, y: 25) == 0 && alpha(in: afterFirstFade, y: 55) > 0,
                     "The first trail should expire before the second")
        view.clear()
        precondition(alpha(in: render(view), y: 55) == 0, "Clearing should remove all remaining trails")
    }

    private static func render(_ view: LaserPointerView) -> NSBitmapImageRep {
        let bitmap = CGContext(data: nil, width: Int(view.bounds.width), height: Int(view.bounds.height),
                               bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return NSBitmapImageRep(cgImage: bitmap.makeImage()!)
    }

    private static func alpha(in image: NSBitmapImageRep, y: Int) -> CGFloat {
        image.colorAt(x: 105, y: image.pixelsHigh - 1 - y)!.alphaComponent
    }
}
