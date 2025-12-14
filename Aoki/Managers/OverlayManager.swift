//
//  OverlayManager.swift
//  Aoki
//
//  Manages the overlay windows and capture workflow.
//
//  Workflow:
//  1. showOverlay() - dims screen, waits for user to draw rectangle
//  2. User drags to draw rectangle
//  3. On mouse release - capture starts immediately
//  4. User scrolls through content
//  5. User clicks - capture stops, image saved, overlay hides
//

import SwiftUI
import os.log

private let logger = OSLog(subsystem: "com.aoki.scrollingscreenshot", category: "OverlayManager")

/// Phases of the capture workflow
enum CapturePhase {
    case idle           // Overlay hidden, waiting for hotkey
    case drawing        // User is drawing the selection rectangle
    case capturing      // Actively capturing frames while user scrolls
}

class OverlayManager {

    // MARK: - Properties

    private(set) var phase: CapturePhase = .idle
    private(set) var rectangle: NSRect = .zero
    private var drawStartPoint: NSPoint = .zero
    private var overlayWindows: [OverlayWindow] = []
    private var overlayViews: [OverlayView] = []
    private var captureTimer: Timer?
    private let stitchingManager = StitchingManager()

    /// Current quality mode - can be changed via menu
    var qualityMode: QualityMode = .reading

    // MARK: - Public API

    /// Shows the overlay on all screens, ready for the user to draw a rectangle.
    func showOverlay() {
        guard phase == .idle else {
            os_log("showOverlay() called but phase is not idle: %{public}@", log: logger, type: .error, String(describing: phase))
            return
        }

        os_log("showOverlay() called - starting capture workflow", log: logger, type: .info)

        phase = .drawing
        rectangle = .zero
        overlayViews.removeAll()

        overlayWindows = NSScreen.screens.map { screen in
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            // Use popUpMenu level to ensure overlay is above text fields
            // that would otherwise fight for cursor control
            window.level = .popUpMenu
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false
            window.hasShadow = false

            let overlayView = OverlayView(manager: self, screenFrame: screen.frame)
            window.contentView = overlayView
            overlayViews.append(overlayView)

            return window
        }

        // First show all windows
        for window in overlayWindows {
            window.orderFrontRegardless()
        }

        // Activate app and make first window key
        NSApp.activate(ignoringOtherApps: true)

        if let firstWindow = overlayWindows.first {
            firstWindow.makeKeyAndOrderFront(nil)
            firstWindow.makeFirstResponder(firstWindow.contentView)
        }

        // Start cursor refresh timer to overcome apps like Terminal
        // that aggressively reset the cursor
        overlayViews.forEach { $0.startCursorRefreshTimer() }

        os_log("Overlay shown, phase: drawing, screens: %{public}d", log: logger, type: .info, overlayWindows.count)
    }

    /// Hides all overlays and resets state.
    func hideOverlay() {
        os_log("hideOverlay() called", log: logger, type: .info)
        stopCapture()

        // Stop cursor refresh timers and remove click monitors
        overlayViews.forEach { $0.stopCursorRefreshTimer() }
        overlayViews.forEach { $0.removeClickMonitor() }

        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        overlayViews.removeAll()
        phase = .idle
        rectangle = .zero
    }

    // MARK: - Drawing Phase

    /// Called when user starts drawing (mouse down).
    func startDrawing(at point: NSPoint) {
        guard phase == .drawing else { return }
        drawStartPoint = point
        rectangle = NSRect(origin: point, size: .zero)
    }

    /// Called as user drags to define rectangle.
    func updateDrawing(to point: NSPoint) {
        guard phase == .drawing else { return }

        let minX = min(drawStartPoint.x, point.x)
        let minY = min(drawStartPoint.y, point.y)
        let width = abs(point.x - drawStartPoint.x)
        let height = abs(point.y - drawStartPoint.y)

        rectangle = NSRect(x: minX, y: minY, width: width, height: height)
        refreshOverlays()
    }

    /// Called when user finishes drawing (mouse up) - starts capture immediately.
    func finishDrawing() {
        guard phase == .drawing else { return }

        // Minimum size check
        guard rectangle.width > 20 && rectangle.height > 20 else {
            hideOverlay()
            return
        }

        startCapture()
    }

    // MARK: - Capture Phase

    /// Starts the scrolling capture.
    private func startCapture() {
        os_log("startCapture() called - rectangle: %{public}@", log: logger, type: .info, String(describing: rectangle))
        phase = .capturing

        // Stop cursor refresh timer since we're leaving drawing phase
        overlayViews.forEach { $0.stopCursorRefreshTimer() }

        // Allow mouse events to pass through so user can scroll
        overlayWindows.forEach { $0.ignoresMouseEvents = true }

        // Setup click monitors on all views to detect stop click
        overlayViews.forEach { $0.setupClickMonitor() }

        refreshOverlays()

        // Take first screenshot
        Task {
            if let image = await captureSingleScreenshot(rectangle) {
                stitchingManager.startStitching(with: image)
                os_log("First screenshot captured: %{public}@", log: logger, type: .info, String(describing: image.size))
            } else {
                os_log("FAILED to capture first screenshot!", log: logger, type: .error)
            }

            await MainActor.run {
                setupCaptureTimer()
            }
        }
    }

    /// Stops capturing and saves the stitched image.
    private func stopCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    /// Called when user clicks to stop capture.
    func userClickedToStop() {
        guard phase == .capturing else {
            os_log("userClickedToStop() called but phase is not capturing", log: logger, type: .error)
            return
        }
        os_log("userClickedToStop() called - saving image...", log: logger, type: .info)

        // Stop the timer first
        captureTimer?.invalidate()
        captureTimer = nil

        // Save the stitched image before hiding overlay
        let mode = self.qualityMode
        Task {
            if let finalImage = await stitchingManager.stopStitching() {
                os_log("Got final stitched image: %{public}@, mode: %{public}@", log: logger, type: .info, String(describing: finalImage.size), mode == .reading ? "Reading" : "Design")
                if let savedURL = saveImage(finalImage, mode: mode) {
                    os_log("Image saved to: %{public}@", log: logger, type: .info, savedURL.path)
                } else {
                    os_log("FAILED to save image!", log: logger, type: .error)
                }
            } else {
                os_log("No stitched image returned from StitchingManager!", log: logger, type: .error)
            }

            // Hide overlay on main thread after save completes
            await MainActor.run {
                self.hideOverlayInternal()
            }
        }
    }

    /// Internal method to hide overlay without stopping capture (already stopped).
    private func hideOverlayInternal() {
        os_log("hideOverlayInternal() called", log: logger, type: .info)

        // Stop cursor refresh timers and remove click monitors
        overlayViews.forEach { $0.stopCursorRefreshTimer() }
        overlayViews.forEach { $0.removeClickMonitor() }

        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        overlayViews.removeAll()
        phase = .idle
        rectangle = .zero
    }

    private func setupCaptureTimer() {
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.phase == .capturing else { return }

            Task {
                if let newImage = await captureSingleScreenshot(self.rectangle) {
                    self.stitchingManager.addImage(newImage)
                }
            }
        }
    }

    // MARK: - Overlay Refresh

    private func refreshOverlays() {
        overlayWindows.forEach { $0.contentView?.needsDisplay = true }
    }
}

// MARK: - Custom Window

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
