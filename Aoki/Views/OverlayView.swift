//
//  OverlayView.swift
//  Aoki
//
//  The main overlay view that handles drawing and mouse events.
//

import AppKit

class OverlayView: NSView {

    // MARK: - Properties

    private weak var manager: OverlayManager?
    private let screenFrame: NSRect
    private var clickMonitor: Any?
    private var escapeMonitor: Any?

    // MARK: - Initialization

    init(manager: OverlayManager, screenFrame: NSRect) {
        self.manager = manager
        self.screenFrame = screenFrame
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))

        // Setup escape key monitor to cancel overlay
        setupEscapeMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Cursor Management

    override func resetCursorRects() {
        super.resetCursorRects()

        // Only show crosshair during drawing phase
        if let manager = manager, manager.phase == .drawing {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    /// Call this to refresh the cursor when phase changes
    func updateCursor() {
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let manager = manager else { return }

        // Draw semi-transparent overlay
        Constants.Overlay.backgroundColor.setFill()
        NSBezierPath(rect: bounds).fill()

        // Draw the selection rectangle if it exists
        let rect = manager.rectangle
        guard rect.width > 0 && rect.height > 0 else { return }

        // Convert global rect to local coordinates
        let localRect = NSRect(
            x: rect.origin.x - screenFrame.origin.x,
            y: rect.origin.y - screenFrame.origin.y,
            width: rect.width,
            height: rect.height
        )

        // Clear the rectangle area (make it transparent)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(localRect)
        context.restoreGState()

        // Draw border
        let borderPath = NSBezierPath(rect: localRect)

        if manager.phase == .capturing {
            // Solid red border during capture
            Constants.SelectionRectangle.capturingBorderColor.setStroke()
            borderPath.lineWidth = Constants.SelectionRectangle.capturingBorderWidth
        } else {
            // Dashed white border while drawing
            Constants.SelectionRectangle.borderColor.setStroke()
            borderPath.lineWidth = Constants.SelectionRectangle.borderWidth
            let dashPattern = Constants.SelectionRectangle.borderDashPattern
            borderPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        }

        borderPath.stroke()
    }

    // MARK: - Mouse Events (Drawing Phase)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard let manager = manager, manager.phase == .drawing else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(
            x: localPoint.x + screenFrame.origin.x,
            y: localPoint.y + screenFrame.origin.y
        )

        manager.startDrawing(at: globalPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let manager = manager, manager.phase == .drawing else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(
            x: localPoint.x + screenFrame.origin.x,
            y: localPoint.y + screenFrame.origin.y
        )

        manager.updateDrawing(to: globalPoint)
    }

    override func mouseUp(with event: NSEvent) {
        guard let manager = manager, manager.phase == .drawing else { return }
        manager.finishDrawing()
    }

    // MARK: - Event Monitors

    /// Sets up escape key monitor to cancel overlay at any phase.
    private func setupEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.keyCode == 53 { // Escape key
                self.manager?.hideOverlay()
                return nil // Consume the event
            }
            return event
        }
    }

    /// Sets up a global click monitor to detect when user clicks to stop capture.
    /// Called only when entering capture phase.
    func setupClickMonitor() {
        guard clickMonitor == nil else { return }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, let manager = self.manager else { return }

            if manager.phase == .capturing {
                DispatchQueue.main.async {
                    manager.userClickedToStop()
                }
            }
        }
    }

    /// Removes the click monitor. Called when exiting capture phase.
    func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
