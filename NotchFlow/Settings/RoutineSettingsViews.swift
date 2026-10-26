import SwiftUI

struct RoutineBreakSettings: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        SettingsGroup(title: "Healthy breaks", footer: "Gentle reminders in the notch. Snooze for 5 minutes or dismiss at any time.") {
            SettingsToggleRow(symbol: "eye", color: Theme.accent, title: "Eye breaks",
                              subtitle: "Look into the distance for 20 seconds", isOn: $store.settings.eyeBreaksEnabled)
            SettingsSliderRow(symbol: "clock", color: Theme.accent, title: "Eye break interval",
                              value: Binding(get: { Double(store.settings.eyeBreakMinutes) }, set: { store.settings.eyeBreakMinutes = Int($0) }),
                              range: 15...180, step: 5, format: { String(localized: "\(Int($0)) min") })
                .disabled(!store.settings.eyeBreaksEnabled)
            SettingsToggleRow(symbol: "figure.stand", color: Theme.accent, title: "Posture breaks",
                              subtitle: "Stand up and change your posture", isOn: $store.settings.postureBreaksEnabled)
            SettingsSliderRow(symbol: "clock", color: Theme.accent, title: "Posture break interval",
                              value: Binding(get: { Double(store.settings.postureBreakMinutes) }, set: { store.settings.postureBreakMinutes = Int($0) }),
                              range: 15...180, step: 5, format: { String(localized: "\(Int($0)) min") })
                .disabled(!store.settings.postureBreaksEnabled)
        }
    }
}

struct DashboardModuleSettings: View {
    @EnvironmentObject private var store: Store

    private var visible: [String] { DashboardModule.normalized(store.settings.dashboardModules) }
    private var ordered: [DashboardModule] {
        visible.compactMap(DashboardModule.init(rawValue:)) + DashboardModule.allCases.filter { !visible.contains($0.rawValue) }
    }

    var body: some View {
        SettingsGroup(title: "Notch modules", footer: "Choose the visible tabs and their order. Keep at least one module visible.") {
            ForEach(ordered) { module in
                SettingsRow(symbol: module.symbol, color: Theme.accent, title: module.rawValue) {
                    HStack(spacing: 8) {
                        Button { move(module, by: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(visible.first == module.rawValue || !visible.contains(module.rawValue))
                            .accessibilityLabel(Text("Move up"))
                        Button { move(module, by: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(visible.last == module.rawValue || !visible.contains(module.rawValue))
                            .accessibilityLabel(Text("Move down"))
                        Toggle(module.rawValue.localized, isOn: Binding(
                            get: { visible.contains(module.rawValue) },
                            set: { enabled in
                                if enabled { store.settings.dashboardModules = visible + [module.rawValue] }
                                else if visible.count > 1 { store.settings.dashboardModules = visible.filter { $0 != module.rawValue } }
                            }))
                            .labelsHidden().toggleStyle(.switch)
                            .disabled(visible.count == 1 && visible.contains(module.rawValue))
                    }
                }
            }
        }
    }

    private func move(_ module: DashboardModule, by offset: Int) {
        var modules = visible
        guard let index = modules.firstIndex(of: module.rawValue), modules.indices.contains(index + offset) else { return }
        modules.swapAt(index, index + offset)
        store.settings.dashboardModules = modules
    }
}
