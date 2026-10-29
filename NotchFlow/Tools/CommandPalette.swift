import SwiftUI

private final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CommandPaletteController {
    private var panel: NSPanel?
    func show(store: Store, run: @escaping (PaletteCommand) -> Void) {
        if let panel, panel.isVisible { panel.close(); return }
        let panel = CommandPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                                 styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Command palette")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CommandPaletteView(onRun: { [weak panel] command in
            panel?.close()
            run(command)
        }, onClose: { [weak panel] in panel?.close() }).environmentObject(store))
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject private var store: Store
    let onRun: (PaletteCommand) -> Void
    let onClose: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool
    private var commands: [PaletteCommand] {
        let actions = PaletteAction.allCases.map { PaletteCommand(id: $0.rawValue, title: $0.rawValue, symbol: $0.symbol, action: $0) }
        let tasks = store.tasks.filter { !$0.isDone }.map {
            PaletteCommand(id: $0.id.uuidString, title: $0.title, symbol: "play.circle", taskID: $0.id)
        }
        return (actions + tasks).filter { $0.matches(query, localizedTitle: $0.action == nil ? $0.title : $0.title.localized) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Theme.accent)
            TextField("Search actions or tasks", text: $query)
                .textFieldStyle(.plain).font(.system(size: 15)).focused($searchFocused)
                .onSubmit { activate() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                Text("esc").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                    .padding(5).background(Theme.control, in: RoundedRectangle(cornerRadius: 5))
            }.padding(20)
            Divider().overlay(Theme.border)
            HStack {
                Text(query.isEmpty ? "Actions & tasks" : "Search results")
                Spacer()
                Text("\(commands.count)").monospacedDigit()
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20).padding(.vertical, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            Button { onRun(command) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: command.symbol).foregroundStyle(Theme.accent)
                                        .frame(width: 30, height: 30)
                                        .background(Theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                                    Text(command.action == nil ? command.title : command.title.localized).font(.system(size: 12, weight: index == selected ? .semibold : .regular)).lineLimit(1)
                                    Spacer()
                                    if command.taskID != nil { Text("Start focus").font(.caption).foregroundStyle(.secondary) }
                                    if index == selected { Image(systemName: "return").foregroundStyle(.secondary) }
                                }.padding(10).frame(maxWidth: .infinity)
                                    .background(index == selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(FlowCompactButtonStyle()).id(index)
                                .accessibilityAddTraits(index == selected ? .isSelected : [])
                        }
                    }.padding(.horizontal, 10)
                }
                .onChange(of: selected) { _, index in proxy.scrollTo(index) }
            }
            if commands.isEmpty { FlowEmptyState(symbol: "magnifyingglass", title: "No matching actions", detail: "Try a different search.") }
            HStack { Text("↑ ↓  ·  ↩"); Spacer(); Button("Close", action: onClose).keyboardShortcut(.cancelAction) }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
                .background(Theme.control)
        }.frame(width: 560, height: 420).background(Theme.windowBackground).flowAppearance()
            .onAppear { searchFocused = true }
            .onChange(of: query) { _, _ in selected = 0 }
    }
    private func move(_ offset: Int) { selected = max(0, min(max(0, commands.count - 1), selected + offset)) }
    private func activate() { if commands.indices.contains(selected) { onRun(commands[selected]) } }
}
