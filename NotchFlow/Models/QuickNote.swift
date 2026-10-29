import Foundation

struct QuickNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var updatedAt = Date()
    static let limit = 10000
    var title: String {
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return String(line.prefix(Task.titleLimit))
    }
}

enum ToolsSection: String, CaseIterable, Identifiable {
    case notes = "Quick notes", clipboard = "Clipboard", files = "File shelf", audio = "Audio mixer"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .files: return "tray.and.arrow.down"
        case .audio: return "slider.horizontal.3"
        }
    }
}
