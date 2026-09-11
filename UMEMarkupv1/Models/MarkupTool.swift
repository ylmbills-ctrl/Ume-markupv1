import SwiftUI

enum MarkupTool: String, CaseIterable, Identifiable {
    case hand
    case highlight
    case underline
    case ink
    case note
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hand: return "Scroll"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .ink: return "Ink"
        case .note: return "Note"
        case .eraser: return "Eraser"
        }
    }

    /// Compact toolbar caption. Drawing tools remind that Apple Pencil marks.
    var toolbarCaption: String {
        if usesPencilOnlyDrawing {
            return "\(title) · Pencil"
        }
        return title
    }

    var systemImage: String {
        switch self {
        case .hand: return "hand.draw"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .ink: return "pencil.tip"
        case .note: return "note.text"
        case .eraser: return "eraser"
        }
    }

    var capturesPageDrag: Bool {
        self == .underline
    }

    var capturesPageTap: Bool {
        self == .note || self == .eraser
    }

    var enablesInkCanvas: Bool {
        self == .ink || self == .highlight || self == .eraser
    }

    /// Ink, freehand highlight, and stroke erase accept Apple Pencil only.
    var usesPencilOnlyDrawing: Bool {
        self == .ink || self == .highlight || self == .eraser
    }

    /// Only the selection-based underline drag still owns one-finger panning.
    /// Ink / highlight / eraser leave the document scroll view on so a finger can pan.
    var blocksDocumentScroll: Bool {
        self == .underline
    }
}

enum MarkupPalette {
    static let swatches: [Color] = [
        Color(red: 1.00, green: 0.92, blue: 0.23),
        Color(red: 1.00, green: 0.68, blue: 0.27),
        Color(red: 1.00, green: 0.45, blue: 0.55),
        Color(red: 0.40, green: 0.87, blue: 0.47),
        Color(red: 0.35, green: 0.62, blue: 1.00),
        Color(red: 0.67, green: 0.47, blue: 1.00),
        Color(red: 0.95, green: 0.28, blue: 0.28),
        Color(red: 0.12, green: 0.12, blue: 0.14)
    ]

    static let defaultHighlight = swatches[0]
    static let defaultInk = swatches[7]
}
