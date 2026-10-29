import Foundation

enum PaletteAction: String, CaseIterable {
    case capture = "Quick capture", focus = "Start or stop focus", water = "Record water"
    case tasks = "Tasks", notes = "Quick notes", clipboard = "Clipboard", files = "File shelf"
    case music = "Music", musicToggle = "Play or pause music", musicNext = "Next track", musicPrevious = "Previous track"
    case ai = "AI usage", settings = "Settings", audio = "Audio mixer"
    var symbol: String {
        switch self {
        case .capture, .notes: return "square.and.pencil"
        case .focus: return "hourglass"
        case .water: return "drop.fill"
        case .tasks: return "checklist"
        case .clipboard: return "doc.on.clipboard"
        case .files: return "tray.and.arrow.down"
        case .music, .musicToggle, .musicNext, .musicPrevious: return "music.note"
        case .ai: return "sparkles"
        case .settings: return "gearshape"
        case .audio: return "slider.horizontal.3"
        }
    }
}

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var action: PaletteAction?
    var taskID: UUID?

    func matches(_ query: String, localizedTitle: String) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace)
        let text = title + " " + localizedTitle
        return tokens.allSatisfy { text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
