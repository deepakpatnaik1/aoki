//
//  Constants.swift
//  Aoki
//

import SwiftUI

struct Constants {
    /// Save directory for all screenshots
    static let saveDirectory = "/Users/d.patnaik/code/aoki-stills"

    /// Date format for screenshot filenames
    static let dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

    struct SelectionRectangle {
        static let borderWidth: CGFloat = 2.0
        static let borderDashPattern: [CGFloat] = [6.0, 4.0]
        static let borderColor: NSColor = .white
        static let capturingBorderColor: NSColor = .red
        static let capturingBorderWidth: CGFloat = 3.0
    }

    struct Overlay {
        static let backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.3)
    }

    struct Hotkey {
        /// "1" key code (for Ctrl+1)
        static let oneKeyCode: Int64 = 18
        /// "2" key code (for Ctrl+2)
        static let twoKeyCode: Int64 = 19
    }

    struct Quality {
        /// JPEG compression for Reading mode (0.0 - 1.0)
        static let readingModeCompression: CGFloat = 0.75
    }
}

/// Quality mode for screenshots
enum QualityMode {
    case reading  // JPEG 75%, for text/content consumption
    case design   // PNG lossless, full quality for design work
}
