# Aoki

Screenshot menu bar app for macOS with two capture modes.

## Quick Reference

- **Ctrl+1**: Window screenshot (captures active window → clipboard + Yoink)
- **Ctrl+2**: Scrolling screenshot (draw rectangle → scroll → click to stop)
- **Output**: `/Users/d.patnaik/code/aoki-stills/`
- **Quality toggle**: Reading Mode (JPEG) / Design Mode (PNG) via menu bar

## Architecture

```
App/           → Entry point + menu bar (AppDelegate)
Managers/      → HotkeyManager, OverlayManager, StitchingManager
Views/         → OverlayView (drawing + mouse events)
Utilities/     → Constants, ScreenshotUtilities
```

## Key Technical Details

- **Hotkey**: CGEvent tap (requires Accessibility permission)
- **Capture**: ScreenCaptureKit (requires Screen Recording permission)
- **Stitching**: Vision framework VNTranslationalImageRegistrationRequest
- **Sandbox**: Disabled (required for CGEvent tap + file access)
- **Signing**: Developer ID Application (Team: NG9X4L83KH)

## Full Documentation

See `../docs/Aoki/documentation.md` for complete details including:
- Detailed workflow and features
- Component descriptions
- Configuration options
- Troubleshooting guide
