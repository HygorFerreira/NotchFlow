import SwiftUI
import Charts

private let waterColor = Color(red: 0.30, green: 0.76, blue: 0.96)

private func waterVolume(_ milliliters: Int) -> String {
    if milliliters < 1000 { return "\(milliliters) ml" }
    return "\((Double(milliliters) / 1000).formatted(.number.precision(.fractionLength(0...2)))) L"
}

struct WaterDashboardView: View {
    @EnvironmentObject private var store: Store
    var onCustomize: (() -> Void)? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let total = store.waterTotal(on: timeline.date)
            let settings = store.hydrationSettings
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(waterColor.opacity(0.13), lineWidth: 7)
                    Circle().trim(from: 0, to: min(1, Double(total) / Double(settings.goalMilliliters)))
                        .stroke(waterColor.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Image(systemName: "drop.fill").foregroundStyle(waterColor)
                        Text(waterVolume(total)).font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Today").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 120, height: 120)
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Water", systemImage: "drop.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button {
                            if let onCustomize { onCustomize() }
                            else { AppDelegate.shared?.showWaterWindow() }
                        } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Water settings and history")
                        .accessibilityLabel("Water settings and history")
                    }
                    Text(total >= settings.goalMilliliters
                         ? String(localized: "Daily goal reached")
                         : String(localized: "Daily goal: \(waterVolume(settings.goalMilliliters))"))
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    Picker("Container", selection: containerBinding) {
                        ForEach(HydrationSettings.Container.allCases) { container in
                            Text(container.title.localized).tag(container)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    HStack {
                        Button { store.recordWater() } label: {
                            Label("+ \(waterVolume(settings.servingMilliliters))", systemImage: settings.container.symbol)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FlowButtonStyle(prominent: true))
                        Button {
                            if let intake = store.waterIntakes(on: timeline.date).first { store.deleteWaterIntake(intake) }
                        } label: { Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28) }
                        .buttonStyle(.plain)
                        .disabled(store.waterIntakes(on: timeline.date).isEmpty)
                        .help("Undo last water entry")
                        .accessibilityLabel("Undo last water entry")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 178)
            .flowSurface()
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var containerBinding: Binding<HydrationSettings.Container> {
        Binding(get: { store.hydrationSettings.container }, set: {
            var settings = store.hydrationSettings
            settings.container = $0
            store.updateHydrationSettings(settings)
        })
    }
}

struct WaterWindowView: View {
    @EnvironmentObject private var store: Store
    @State private var draft = HydrationSettings()
    @State private var liters = false
    @State private var didSave = false

    @State private var showSettings = false
    @State private var glassInput = "250"
    @State private var bottleInput = "500"

    private var glassCapacity: Int? { HydrationSettings.capacity(from: glassInput, inLiters: liters) }
    private var bottleCapacity: Int? { HydrationSettings.capacity(from: bottleInput, inLiters: liters) }
    private var validSettings: Bool { glassCapacity != nil && bottleCapacity != nil }
    private var isDirty: Bool {
        glassCapacity != store.hydrationSettings.glassMilliliters
            || bottleCapacity != store.hydrationSettings.bottleMilliliters
            || draft.goalMilliliters != store.hydrationSettings.goalMilliliters
            || draft.remindersEnabled != store.hydrationSettings.remindersEnabled
            || draft.reminderIntervalMinutes != store.hydrationSettings.reminderIntervalMinutes
    }
    private func reloadDraft() {
        draft = store.hydrationSettings
        glassInput = volumeInput(draft.glassMilliliters)
        bottleInput = volumeInput(draft.bottleMilliliters)
        didSave = false
    }
    private func volumeInput(_ ml: Int) -> String {
        (Double(ml) / (liters ? 1000 : 1)).formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FlowPageHeading(title: "Water", subtitle: "Your container, your daily rhythm", symbol: "drop.fill", color: waterColor)
                    WaterDashboardView(onCustomize: { showSettings.toggle() })
                    DisclosureGroup(isExpanded: $showSettings) {
                        settingsCard.padding(.top, 14)
                    } label: {
                        Label("Your water settings", systemImage: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(18)
                    .flowSurface()
                    weeklyChart(at: timeline.date)
                    history(at: timeline.date)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 620, minHeight: 640)
        .background(Theme.windowBackground)
        .safeAreaInset(edge: .top, spacing: 0) { FlowWindowNavigation(current: .water) }
        .flowAppearance()
        .onAppear { reloadDraft() }
        .onChange(of: draft) { _, _ in didSave = false }
        .onChange(of: glassInput) { _, _ in didSave = false }
        .onChange(of: bottleInput) { _, _ in didSave = false }
        .onChange(of: store.hydrationSettings) { old, new in
            // Container switches never overwrite unsaved volume/goal edits.
            if glassCapacity == old.glassMilliliters && bottleCapacity == old.bottleMilliliters
                && draft.goalMilliliters == old.goalMilliliters
                && draft.remindersEnabled == old.remindersEnabled
                && draft.reminderIntervalMinutes == old.reminderIntervalMinutes { reloadDraft() }
        }
        .onChange(of: liters) { old, _ in
            let glass = HydrationSettings.capacity(from: glassInput, inLiters: old)
            let bottle = HydrationSettings.capacity(from: bottleInput, inLiters: old)
            if let glass { glassInput = volumeInput(glass) }
            if let bottle { bottleInput = volumeInput(bottle) }
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Container capacity").font(.subheadline.weight(.medium))
                Spacer()
                Picker("Unit", selection: $liters) {
                    Text("ml").tag(false)
                    Text("L").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .disabled(!validSettings)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Glass", systemImage: "mug").font(.caption).foregroundStyle(.secondary)
                    TextField("Capacity", text: $glassInput)
                        .textFieldStyle(FlowTextFieldStyle())
                        .accessibilityLabel("Glass capacity")
                }
                VStack(alignment: .leading, spacing: 7) {
                    Label("Bottle", systemImage: "waterbottle").font(.caption).foregroundStyle(.secondary)
                    TextField("Capacity", text: $bottleInput)
                        .textFieldStyle(FlowTextFieldStyle())
                        .accessibilityLabel("Bottle capacity")
                }
            }
            Text("Choose a capacity from 50 ml to 3 L. Glass and bottle sizes are saved separately.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Stepper(value: $draft.goalMilliliters, in: HydrationSettings.goalRange, step: 250) {
                Text("Daily goal: \(waterVolume(draft.goalMilliliters))")
            }
            Toggle("Water reminders below the notch", isOn: $draft.remindersEnabled)
            if draft.remindersEnabled {
                Picker("Reminder interval", selection: $draft.reminderIntervalMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                        Text("Every \(minutes) minutes").tag(minutes)
                    }
                }
                Text("Reminders appear while the app is running, from 8 am to 10 pm, until your daily goal is reached.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Text(didSave ? String(localized: "Settings saved") : String(localized: "Each entry uses the selected container's full capacity."))
                    .font(.caption).foregroundStyle(didSave ? Theme.success : Theme.textSecondary)
                Spacer()
                Button("Save settings") {
                    guard let glassCapacity, let bottleCapacity else { return }
                    var settings = store.hydrationSettings
                    settings.glassMilliliters = glassCapacity
                    settings.bottleMilliliters = bottleCapacity
                    settings.goalMilliliters = draft.goalMilliliters
                    settings.remindersEnabled = draft.remindersEnabled
                    settings.reminderIntervalMinutes = draft.reminderIntervalMinutes
                    store.updateHydrationSettings(settings)
                    didSave = store.persistenceError == nil
                }
                .buttonStyle(FlowButtonStyle(prominent: true))
                .disabled(!validSettings || (!isDirty && store.persistenceError == nil))
                if isDirty {
                    Button("Cancel") { reloadDraft() }.buttonStyle(FlowButtonStyle())
                }
            }
            if !validSettings {
                Text("Enter a valid capacity between 50 ml and 3 L.").font(.caption).foregroundStyle(.orange)
            }
            Text("Changing the container size keeps previous entries unchanged.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func weeklyChart(at date: Date) -> some View {
        let calendar = Calendar.current
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: calendar.startOfDay(for: date)) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Water in the last 7 days").font(.headline)
            Chart(days, id: \.self) { day in
                BarMark(x: .value("Day", day, unit: .day), y: .value("ml", store.waterTotal(on: day)))
                    .foregroundStyle(waterColor.gradient)
                    .cornerRadius(4)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue(waterVolume(store.waterTotal(on: day)))
            }
            .chartXAxis {
                AxisMarks(values: days) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) }
            }
            .chartYAxisLabel("ml")
            .frame(height: 150)
        }
        .padding(18)
        .flowSurface()
    }

    private func history(at date: Date) -> some View {
        let entries = store.waterIntakes(on: date)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Today's water entries").font(.headline)
            if entries.isEmpty {
                Label("No water logged yet", systemImage: "drop")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .flowSurface()
            }
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.container.symbol).foregroundStyle(waterColor)
                    Text(waterVolume(entry.milliliters)).fontWeight(.semibold)
                    Text(entry.container.title.localized).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(entry.recordedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Button { store.deleteWaterIntake(entry) } label: { Image(systemName: "trash").frame(width: 28, height: 28) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove water entry")
                        .help("Remove water entry")
                }
                .padding(12)
                .flowSurface()
            }
        }
    }
}
