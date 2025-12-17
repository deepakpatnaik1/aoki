//
//  ScreenshotUtilities.swift
//  Aoki
//

import ScreenCaptureKit
import AppKit

// MARK: - Public API

/// Captures a screenshot of the frontmost window and copies it to clipboard + sends to Yoink.
/// Returns true if successful.
@discardableResult
func captureActiveWindow() async -> Bool {
    // Use CGWindowListCreateImage for reliable single-window capture
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

    let currentPID = NSRunningApplication.current.processIdentifier

    // Find the frontmost window (excluding Aoki itself)
    guard let windowInfo = windowList.first(where: { info in
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let width = bounds["Width"],
              let height = bounds["Height"],
              let layer = info[kCGWindowLayer as String] as? Int else {
            return false
        }
        return ownerPID != currentPID &&
               layer == 0 && // Normal window layer
               width > 50 && height > 50
    }),
    let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
    let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
    let x = bounds["X"], let y = bounds["Y"],
    let width = bounds["Width"], let height = bounds["Height"] else {
        print("No suitable window found for capture")
        return false
    }

    let windowRect = CGRect(x: x, y: y, width: width, height: height)
    let windowName = windowInfo[kCGWindowOwnerName as String] as? String ?? "Unknown"

    // Capture the specific window
    guard let cgImage = CGWindowListCreateImage(
        windowRect,
        .optionIncludingWindow,
        windowID,
        [.boundsIgnoreFraming, .bestResolution]
    ) else {
        print("Failed to capture window image")
        return false
    }

    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

    // Copy to clipboard
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([nsImage])

    // Save to file and send to Yoink
    saveImage(nsImage, mode: .reading)

    print("Window screenshot captured: \(windowName) (\(Int(width))x\(Int(height)))")
    return true
}

/// Captures a single screenshot of the specified rectangle on the active screen.
/// Uses native Retina resolution for crisp text, saved as JPEG for small file sizes.
func captureSingleScreenshot(_ rectangle: NSRect) async -> NSImage? {
    guard let activeScreen = screenContainingPoint(rectangle.origin),
          let currentApp = await findCurrentSCApplication(),
          let display = await getSCDisplay(from: activeScreen) else {
        print("Error: Unable to determine active screen or display.")
        return nil
    }

    let adjustedRect = adjustRectForScreen(rectangle, for: activeScreen)
    let filter = SCContentFilter(display: display, excludingApplications: [currentApp], exceptingWindows: [])

    // Use native Retina resolution for sharp text
    let scaleFactor = Int(filter.pointPixelScale)
    let width = Int(adjustedRect.width) * scaleFactor
    let height = Int(adjustedRect.height) * scaleFactor

    let config = SCStreamConfiguration()
    config.sourceRect = adjustedRect
    config.width = width
    config.height = height
    config.colorSpaceName = CGColorSpace.sRGB
    config.showsCursor = false

    do {
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let nsImage = NSImage(cgImage: image, size: adjustedRect.size)
        return nsImage
    } catch {
        print("Error capturing screenshot: \(error.localizedDescription)")
        return nil
    }
}

/// Saves the captured image to the configured save directory.
/// - Parameters:
///   - image: The `NSImage` to save.
///   - mode: Quality mode - `.reading` for JPEG (small files), `.design` for PNG (lossless)
/// - Returns: A `URL` to the saved file, or `nil` if saving fails.
@discardableResult
func saveImage(_ image: NSImage, mode: QualityMode = .reading) -> URL? {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData) else {
        print("Failed to create bitmap representation.")
        return nil
    }

    let imageData: Data?
    let fileExtension: String

    switch mode {
    case .reading:
        // JPEG at 75% quality - small files, readable text
        imageData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: Constants.Quality.readingModeCompression]
        )
        fileExtension = "jpg"
    case .design:
        // PNG lossless - crystal clear for design work
        imageData = bitmapRep.representation(using: .png, properties: [:])
        fileExtension = "png"
    }

    guard let data = imageData else {
        print("Failed to generate image data.")
        return nil
    }

    let filename = getFileName(extension: fileExtension)
    let saveDirectory = URL(fileURLWithPath: Constants.saveDirectory)
    let fileURL = saveDirectory.appendingPathComponent(filename)

    // Ensure directory exists
    do {
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
    } catch {
        print("Failed to create save directory: \(error.localizedDescription)")
        return nil
    }

    do {
        try data.write(to: fileURL)
        print("Screenshot saved to: \(fileURL.path) (\(mode == .reading ? "Reading" : "Design") mode)")
        sendToYoink(fileURL)
        return fileURL
    } catch {
        print("Failed to save image: \(error.localizedDescription)")
        return nil
    }
}

/// Sends the file to Yoink for easy drag-and-drop access.
private func sendToYoink(_ fileURL: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Yoink", fileURL.path]

    do {
        try process.run()
    } catch {
        print("Failed to send to Yoink: \(error.localizedDescription)")
    }
}

// MARK: - Capture Helpers

private func screenContainingPoint(_ point: NSPoint) -> NSScreen? {
    return NSScreen.screens.first { $0.frame.contains(point) }
}

private func adjustRectForScreen(_ rect: NSRect, for screen: NSScreen) -> NSRect {
    let screenHeight = screen.frame.height + screen.frame.minY
    return NSRect(
        x: rect.origin.x - screen.frame.minX,
        y: screenHeight - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
    )
}

private func getSCDisplay(from nsScreen: NSScreen) async -> SCDisplay? {
    guard let screenID = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        print("Error: Unable to retrieve screen ID.")
        return nil
    }

    do {
        let displays = try await SCShareableContent.current.displays
        return displays.first { $0.displayID == screenID }
    } catch {
        print("Error fetching SCDisplay: \(error)")
        return nil
    }
}

private func findCurrentSCApplication() async -> SCRunningApplication? {
    do {
        let apps = try await SCShareableContent.current.applications
        let currentPID = NSRunningApplication.current.processIdentifier

        if let app = apps.first(where: { $0.processID == currentPID }) {
            return app
        } else {
            print("Current application not found in SCShareableContent.")
            return nil
        }
    } catch {
        print("Error fetching applications: \(error)")
        return nil
    }
}

private func getFileName(extension ext: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = Constants.dateFormat
    let timestamp = dateFormatter.string(from: Date())
    return "Screenshot \(timestamp).\(ext)"
}

// MARK: - Permission Check

/// Checks if screen recording permission is granted, and requests it if not.
func checkScreenRecordingPermission() async -> Bool {
    let isAuthorized = await withCheckedContinuation { continuation in
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            continuation.resume(returning: CGPreflightScreenCaptureAccess())
        }
    }

    if !isAuthorized {
        print("Screen recording permission not granted. Prompting user...")
        CGRequestScreenCaptureAccess()
        return false
    }

    return true
}
