import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum CaptureError: LocalizedError {
    case displayUnavailable, imageUnavailable
    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "캡처할 디스플레이를 찾을 수 없어요."
        case .imageUnavailable: return "캡처 이미지를 만들 수 없어요."
        }
    }
}

enum ScreenCapture {
    static func image(displayID: CGDirectDisplayID, ink: CGImage?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        config.showsCursor = false
        let desktop = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try composite(desktop, ink: ink)
    }

    static func composite(_ desktop: CGImage, ink: CGImage?) throws -> CGImage {
        guard let ink else { return desktop }
        guard let context = CGContext(data: nil, width: desktop.width, height: desktop.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.imageUnavailable
        }
        let rect = CGRect(x: 0, y: 0, width: desktop.width, height: desktop.height)
        context.draw(desktop, in: rect)
        context.draw(ink, in: rect)
        guard let result = context.makeImage() else { throw CaptureError.imageUnavailable }
        return result
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureError.imageUnavailable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.imageUnavailable }
        try (data as Data).write(to: url, options: .atomic)
    }

    @MainActor static func chooseDestination() -> URL? {
        let save = NSSavePanel()
        save.allowedContentTypes = [.png]
        save.canCreateDirectories = true
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd HH-mm-ss"
        save.nameFieldStringValue = "Lines " + date.string(from: Date()) + ".png"
        save.title = "강의 화면 캡처 저장"
        save.level = .screenSaver
        return save.runModal() == .OK ? save.url : nil
    }
}
