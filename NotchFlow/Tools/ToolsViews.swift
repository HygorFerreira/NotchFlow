import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ToolsModel: ObservableObject {
    @Published var section: ToolsSection = .notes
    let clipboard: ClipboardMonitor
    let shelf: FileShelf
    init(isolated: Bool = false) {
        clipboard = ClipboardMonitor(start: !isolated)
        shelf = FileShelf(directory: isolated ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notchflow-preview-shelf-\(UUID())") : nil)
    }
}

struct ToolsView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: ToolsModel
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 20) {
            if !compact {
                FlowPageHeading(title: "Tools", subtitle: "A little space for everything in progress.",
                                symbol: "square.grid.2x2")
            }
            HStack(spacing: 4) {
                ForEach(ToolsSection.allCases) { section in
                    Button { model.section = section } label: {
                        Label(section.rawValue.localized, systemImage: section.symbol)
                            .font(.system(size: 11, weight: model.section == section ? .semibold : .medium))
                            .foregroundStyle(model.section == section ? Theme.textPrimary : Theme.textSecondary)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(model.section == section ? Theme.panel : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(model.section == section ? Theme.border : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FlowCompactButtonStyle())
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 12))
            Group {
                switch model.section {
                case .notes: QuickNotesView(compact: compact)
                case .clipboard: ClipboardHistoryView(monitor: model.clipboard)
                case .files: FileShelfView(shelf: model.shelf)
                case .audio: AudioMixerView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !compact { StorePersistenceBanner() }
        }
        .frame(height: compact ? 220 : nil)
    }
}

struct QuickNotesView: View {
    @EnvironmentObject private var store: Store
    var compact = false
    @State private var selected: UUID?
    @State private var draft = ""
    @State private var deleted: QuickNote?
    @State private var taskCreated = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Button { save(); selected = nil; draft = "" } label: {
                    Label("New note", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(FlowButtonStyle(prominent: true))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.quickNotes) { note in
                            Button { save(); selected = note.id; draft = note.text } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.title.isEmpty ? "Quick note".localized : note.title)
                                        .font(.system(size: 11, weight: .medium)).lineLimit(2)
                                    if !compact {
                                        Text(note.updatedAt, style: .date)
                                            .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(selected == note.id ? Theme.accent.opacity(0.10) : .clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                                .overlay(alignment: .leading) {
                                    if selected == note.id { Capsule().fill(Theme.accent).frame(width: 3, height: 20) }
                                }
                            }.buttonStyle(FlowCompactButtonStyle())
                            .accessibilityAddTraits(selected == note.id ? .isSelected : [])
                        }
                    }
                }
            }.frame(width: compact ? 148 : 190)
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $draft).font(.system(size: compact ? 12 : 13)).scrollContentBackground(.hidden)
                    .padding(10).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("Capture an idea…").font(.system(size: compact ? 12 : 13))
                                .foregroundStyle(Theme.textSecondary).padding(.horizontal, 16).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(Text("Quick note"))
                    .onChange(of: draft) { _, text in
                        taskCreated = false
                        if text.count > QuickNote.limit { draft = String(text.prefix(QuickNote.limit)) }
                    }
                HStack(spacing: 8) {
                    Button("Save note") { save() }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(taskCreated ? "Task created" : "Make task") {
                        save()
                        if let selected { store.convertQuickNote(selected); taskCreated = store.persistenceError == nil }
                    }.disabled(taskCreated || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let id = selected {
                        Button { deleted = store.quickNotes.first { $0.id == id }; store.removeQuickNote(id); selected = nil; draft = "" } label: { Image(systemName: "trash") }
                            .accessibilityLabel(Text("Delete note"))
                    }
                    if let deleted {
                        Button("Undo delete") { selected = store.addQuickNote(deleted.text); draft = deleted.text; self.deleted = nil }
                    }
                    Spacer(minLength: 0)
                }.font(.system(size: 10)).buttonStyle(FlowButtonStyle())
                if !compact {
                    HStack {
                        Label("Saved automatically", systemImage: "checkmark.circle")
                        Spacer()
                        Text("\(draft.count) / \(QuickNote.limit)").monospacedDigit()
                    }.font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onAppear { if selected == nil, let note = store.quickNotes.first { selected = note.id; draft = note.text } }
        .onDisappear { save() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in save() }
        .task(id: draft) {
            do { try await _Concurrency.Task.sleep(for: .milliseconds(500)) }
            catch { return }
            if !_Concurrency.Task.isCancelled { save() }
        }
    }
    private func save() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let selected { if store.quickNotes.first(where: { $0.id == selected })?.text != draft { store.updateQuickNote(selected, text: draft) } }
        else { selected = store.addQuickNote(draft) }
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var query = ""
    private var filteredEntries: [ClipboardEntry] {
        monitor.entries.filter { query.isEmpty || $0.preview.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Clipboard history", isOn: Binding(get: { monitor.enabled }, set: monitor.setEnabled)).toggleStyle(.switch)
                Spacer()
                Button("Clear history") { monitor.clear() }.disabled(monitor.entries.isEmpty)
            }.font(.system(size: 11))
            if monitor.enabled {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search clipboard", text: $query).textFieldStyle(.plain)
                    Text("\(monitor.entries.count)").monospacedDigit().foregroundStyle(Theme.textSecondary)
                }.font(.system(size: 11)).padding(9).background(Theme.control, in: RoundedRectangle(cornerRadius: 9))
                if filteredEntries.isEmpty {
                    FlowEmptyState(symbol: "doc.on.clipboard", title: query.isEmpty ? "Clipboard is ready" : "No matching copies",
                        detail: query.isEmpty ? "New copies appear here while history is enabled." : "Try a different search.")
                } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredEntries) { entry in
                            HStack {
                                if let data = entry.image, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "text.alignleft").foregroundStyle(Theme.accent)
                                        .frame(width: 28, height: 28).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                                }
                                Text(entry.preview).font(.system(size: 11)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Button(monitor.copiedID == entry.id ? "Copied" : "Copy") { monitor.copy(entry) }
                                Button { monitor.remove(entry.id) } label: { Image(systemName: "xmark") }.accessibilityLabel(Text("Remove copy"))
                            }.padding(8).background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                }
            } else {
                FlowEmptyState(symbol: "clipboard", title: "Your copies, within reach",
                    detail: "History is kept only for this session. Disabling it clears all saved copies.")
            }
        }
        .buttonStyle(FlowButtonStyle())
    }
}

struct FileShelfView: View {
    @ObservedObject var shelf: FileShelf
    @State private var targeted = false
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Drop files on the notch", systemImage: "tray.and.arrow.down").font(.system(size: 11))
                Spacer()
                if shelf.busy { ProgressView().controlSize(.small) }
                Button("Add files…") { shelf.pickFiles() }.disabled(shelf.busy)
            }
            if let error = shelf.error { Text(error).font(.caption).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
            if shelf.files.isEmpty {
                FlowEmptyState(symbol: "tray.and.arrow.down", title: "Drop something here",
                    detail: "Keep temporary copies here, then drag them into another app. Originals stay in place.")
            } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155))], spacing: 8) {
                    ForEach(shelf.files) { file in
                        HStack {
                            Image(systemName: "doc.fill").foregroundStyle(Theme.accent)
                            Text(file.name).font(.system(size: 11)).lineLimit(1).help(file.name)
                            Spacer(minLength: 2)
                            Button { shelf.remove(file) } label: { Image(systemName: "trash") }.buttonStyle(.plain).accessibilityLabel(Text("Remove file copy"))
                        }.padding(10).background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
                            .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
                    }
                }
            }
        }
        }
        .padding(12)
        .background(targeted ? Theme.accent.opacity(0.12) : Theme.control, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(targeted ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .buttonStyle(FlowButtonStyle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { shelf.accept($0) }
    }
}

@MainActor
final class ToolsWindowController {
    private let panel: NSPanel
    init(store: Store, model: ToolsModel) {
        panel = ToolsPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Tools")
        panel.minSize = NSSize(width: 640, height: 400)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: ToolsView(model: model).padding(20).background(Theme.windowBackground).flowAppearance().environmentObject(store))
        panel.center()
    }
    func show() { panel.makeKeyAndOrderFront(nil) }
}

private final class ToolsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
