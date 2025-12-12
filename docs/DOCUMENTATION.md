# Aoki - Scrolling Screenshot App

A macOS menu bar application for capturing scrolling screenshots with intelligent image stitching.

## Overview

Aoki lives in your menu bar and listens for the **F17** hotkey. When triggered, it dims the screen with a crosshair cursor, allowing you to draw a rectangle around content. Once the rectangle is drawn, it immediately begins capturing screenshots as you scroll, then stitches them together into a single tall image when you click to stop.

## Workflow

1. **Press F17** - Screen dims with a semi-transparent overlay, crosshair cursor appears
2. **Draw rectangle** - Click and drag to define the capture region (white dashed border)
3. **Release mouse** - Capture begins immediately (border turns solid red)
4. **Scroll through content** - App captures frames at 250ms intervals
5. **Click anywhere** - Capture stops, image is stitched and saved
6. **Press Escape** - Cancel at any time

## Features

- **Global F17 hotkey** - Works from any application
- **Multi-screen support** - Overlay spans all connected displays
- **Quality modes**:
  - **Reading Mode** (default): JPEG at 75% quality - small file sizes, readable text
  - **Design Mode**: PNG lossless - pixel-perfect for design work
- **Bidirectional scrolling** - Supports both upward and downward scrolling
- **Vision-based stitching** - Uses Apple's Vision framework for intelligent image alignment
- **Launch at Login** - Optional auto-start via ServiceManagement
- **Retina support** - Captures at native screen resolution

## Project Structure

```
Aoki/
├── App/
│   ├── AokiApp.swift          # App entry point (@main)
│   └── AppDelegate.swift      # Menu bar setup, hotkey handling
├── Managers/
│   ├── HotkeyManager.swift    # Global F17 hotkey via CGEvent tap
│   ├── OverlayManager.swift   # Capture workflow state machine
│   └── StitchingManager.swift # Vision-based image stitching
├── Views/
│   └── OverlayView.swift      # Overlay drawing and mouse events
├── Utilities/
│   ├── Constants.swift        # Configuration and styling constants
│   └── ScreenshotUtilities.swift  # ScreenCaptureKit integration
├── Assets.xcassets/           # App icon
├── Aoki.entitlements          # Security entitlements
└── Info.plist                 # App configuration
```

## Key Components

### AppDelegate

The main controller that:
- Sets up the menu bar status item with camera icon
- Creates the hotkey manager
- Provides menu items for quality toggle, folder access, launch at login
- Handles the `hotkeyPressed()` delegate callback

### HotkeyManager

Uses `CGEvent.tapCreate()` to listen for global key events:
- Listens for F17 (keycode 64)
- Requires Accessibility permission (`AXIsProcessTrusted()`)
- Runs on the session event tap to catch keys globally

### OverlayManager

State machine managing the capture workflow:
- **Phase: idle** - Waiting for hotkey
- **Phase: drawing** - User is drawing the selection rectangle
- **Phase: capturing** - Timer-based frame capture active

Key methods:
- `showOverlay()` - Creates overlay windows on all screens
- `startDrawing(at:)` / `updateDrawing(to:)` / `finishDrawing()` - Rectangle selection
- `startCapture()` - Begins timer-based frame capture
- `userClickedToStop()` - Stops capture, saves stitched image

### StitchingManager

Uses Apple's Vision framework for intelligent image alignment:
- `VNTranslationalImageRegistrationRequest` - Detects scroll offset between frames
- Supports both downward (composite to bottom) and upward (crop from bottom) scrolling
- Maintains a running stitched image and previous frame for comparison
- Uses a serial dispatch queue (`stitchingQueue`) for thread safety

### OverlayView

Custom NSView for the overlay UI:
- Semi-transparent black background (30% opacity)
- Clear rectangle cutout showing capture region
- Dashed white border (drawing phase) / Solid red border (capturing phase)
- `resetCursorRects()` for proper crosshair cursor
- Event monitors for Escape key and click-to-stop

### ScreenshotUtilities

Functions for screen capture:
- `captureSingleScreenshot(_:)` - Uses ScreenCaptureKit with Retina resolution
- `saveImage(_:mode:)` - Saves as JPEG or PNG based on quality mode
- `checkScreenRecordingPermission()` - Checks/requests screen recording access

## Configuration (Constants.swift)

```swift
// Save location
static let saveDirectory = "/Users/d.patnaik/code/aoki-stills"

// File naming
static let dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

// Capture timing
Timer interval: 0.25 seconds (250ms)

// Quality modes
Reading mode: JPEG 75% compression
Design mode: PNG lossless
```

## Required Permissions

1. **Screen Recording** - For ScreenCaptureKit screenshot capture
2. **Accessibility** - For global hotkey detection (CGEvent tap)

The app requests these permissions on first launch. Without them:
- Screen Recording: Screenshots will fail
- Accessibility: F17 hotkey won't trigger

## Building & Signing

The app is signed with Developer ID for persistent permissions:
- Team ID: NG9X4L83KH
- Code Sign Identity: "Developer ID Application"
- Hardened Runtime: Enabled
- App Sandbox: **Disabled** (required for CGEvent tap and file access)

Build and install:
```bash
xcodebuild -scheme Aoki -configuration Release build
# Copy to /Applications
```

## Known Limitations

- F17 key required (external keyboard or key remapping)
- Sandbox disabled - can't be distributed via Mac App Store
- Screenshots save to hardcoded directory

## Troubleshooting

**Hotkey not working?**
- Check System Preferences > Privacy & Security > Accessibility
- Ensure Aoki is listed and enabled

**Screenshots not capturing?**
- Check System Preferences > Privacy & Security > Screen Recording
- Grant permission and restart app

**Permission prompts on every rebuild?**
- Sign with Developer ID (not ad-hoc)
- Use same Team ID and Bundle ID consistently

## Version History

- **v3.0.0** - Current version with F17 hotkey, quality toggle, Vision-based stitching
