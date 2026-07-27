import AppKit
import ScreenCaptureKit

/// Grabs the desktop underneath the overlay so annotations can be exported as a
/// finished screenshot. Requires the Screen Recording permission; everything
/// else in the app works without it.
enum ScreenCapture {

    enum CaptureError: LocalizedError {
        case displayNotFound
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .displayNotFound:
                return "Could not find the display to capture."
            case .permissionDenied:
                return "Skribble needs Screen Recording permission to capture the screen."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .permissionDenied:
                return "Open System Settings › Privacy & Security › Screen Recording and enable Skribble, then try again."
            case .displayNotFound:
                return nil
            }
        }
    }

    /// Captures `screen` with all of Skribble's own windows excluded, so the
    /// overlay and sidebar never appear in the result.
    static func capture(screen: NSScreen) async throws -> CGImage {
        guard let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID else {
            throw CaptureError.displayNotFound
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.permissionDenied
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let ourApps = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ourApps,
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                          configuration: config)
    }

    /// Whether permission has already been granted, so the UI can warn up front.
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }
}
