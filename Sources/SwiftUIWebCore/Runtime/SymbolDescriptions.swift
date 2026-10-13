// The accessibility description of a system symbol (sw-toolbar-symbol-label, decision 0021):
// SwiftUI labels a control whose only content is `Image(systemName:)` with the symbol's
// localised description ("plus" reads as "Add"). The common ones as SF Symbols names them;
// any other symbol reads as its name with the dots and digits spelled out ("arrow.up.circle"
// → "Arrow Up Circle"), which is close to most descriptions.
package enum _SymbolDescriptions {
    package static func description(of name: String) -> String {
        let base = name.hasSuffix(".fill") ? String(name.dropLast(5)) : name
        if let known = table[base] ?? table[name] { return known }
        return name.split(separator: ".").map { part -> String in
            switch part {
            case "circle": return "Circle"
            case "square": return "Square"
            case "rectangle": return "Rectangle"
            case "slash": return "Slash"
            default: return part.prefix(1).uppercased() + part.dropFirst()
            }
        }.joined(separator: " ")
    }

    private static let table: [String: String] = [
        "plus": "Add", "minus": "Remove", "xmark": "Close", "checkmark": "Checkmark", "trash": "Delete", "pencil": "Edit",
        "square.and.pencil": "Compose", "square.and.arrow.up": "Share", "square.and.arrow.down": "Download",
        "chevron.left": "Back", "chevron.right": "Forward", "chevron.up": "Up", "chevron.down": "Down", "chevron.backward": "Back", "chevron.forward": "Forward",
        "arrow.left": "Back", "arrow.right": "Forward", "arrow.up": "Up", "arrow.down": "Down", "arrow.clockwise": "Refresh", "arrow.counterclockwise": "Reload",
        "arrow.uturn.backward": "Undo", "arrow.uturn.forward": "Redo", "arrow.backward": "Back", "arrow.forward": "Forward",
        "gear": "Settings", "gearshape": "Settings", "magnifyingglass": "Search", "ellipsis": "More", "ellipsis.circle": "More",
        "info": "Info", "info.circle": "Info", "questionmark": "Question Mark", "questionmark.circle": "Help", "exclamationmark.triangle": "Warning",
        "play": "Play", "pause": "Pause", "stop": "Stop", "forward": "Fast Forward", "backward": "Rewind", "forward.end": "Skip to End", "backward.end": "Skip to Beginning",
        "speaker.wave.2": "Speaker", "speaker.slash": "Mute", "mic": "Microphone", "mic.slash": "Microphone Off", "timer": "Timer", "clock": "Clock", "calendar": "Calendar",
        "star": "Star", "heart": "Heart", "bell": "Bell", "bell.slash": "Silence", "flag": "Flag", "tag": "Tag", "bookmark": "Bookmark", "pin": "Pin",
        "house": "Home", "person": "Person", "person.2": "People", "person.badge.plus": "Add Person", "person.crop.circle": "Profile", "person.3": "Group",
        "list.bullet": "List", "line.3.horizontal": "Menu", "slider.horizontal.3": "Sliders", "square.grid.2x2": "Grid", "sidebar.leading": "Sidebar",
        "photo": "Photo", "camera": "Camera", "video": "Video", "map": "Map", "location": "Location", "globe": "Globe", "link": "Link", "paperclip": "Attachment",
        "doc": "Document", "doc.text": "Document", "folder": "Folder", "paperplane": "Send", "envelope": "Mail", "phone": "Phone", "message": "Message", "text.bubble": "Comment",
        "lock": "Lock", "lock.open": "Unlock", "key": "Key", "eye": "Show", "eye.slash": "Hide", "cart": "Cart", "creditcard": "Credit Card", "bag": "Bag",
        "wand.and.stars": "Wand and Stars", "sparkles": "Sparkles", "lightbulb": "Lightbulb", "sun.max": "Sun", "moon": "Moon", "cloud": "Cloud",
        "xmark.circle": "Clear", "plus.circle": "Add", "minus.circle": "Remove", "checkmark.circle": "Done", "arrow.up.circle": "Up", "arrow.down.circle": "Down",
        "hand.thumbsup": "Thumbs Up", "hand.thumbsdown": "Thumbs Down", "trash.slash": "Restore", "crop": "Crop", "rotate.left": "Rotate Left", "rotate.right": "Rotate Right",
        "textformat": "Text Format", "bold": "Bold", "italic": "Italic", "underline": "Underline", "increase.indent": "Increase Indent", "decrease.indent": "Decrease Indent",
        "arrow.up.arrow.down": "Sort", "line.3.horizontal.decrease.circle": "Filter", "arrow.triangle.2.circlepath": "Sync", "icloud": "iCloud", "wifi": "Wi-Fi",
        "battery.100": "Battery", "power": "Power", "printer": "Print", "scissors": "Cut", "doc.on.doc": "Copy", "doc.on.clipboard": "Paste",
    ]
}
