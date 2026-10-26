import SwiftUI
import AppKit

struct UpcomingEventRow: View {
    @EnvironmentObject private var vm: NotchViewModel
    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").foregroundStyle(Theme.accent)
            if let event = vm.upcomingEvent {
                Text(event.start, format: .dateTime.hour().minute())
                    .monospacedDigit().foregroundStyle(Theme.textSecondary)
                Text(event.title).lineLimit(1).help(event.title)
                Spacer(minLength: 4)
                Text(event.start <= Date() ? String(localized: "Now") : event.start.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Button(event.meetingURL == nil ? "Open event" : "Join meeting") {
                    if let url = event.meetingURL { NSWorkspace.shared.open(url) }
                    else { showingDetails = true }
                }
                .buttonStyle(FlowButtonStyle())
            } else {
                Text(vm.calendarAuthorized ? "No upcoming events" : "Connect your calendar")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(vm.calendarAuthorized ? "Calendar" : "Connect…") {
                    if vm.calendarAuthorized { openCalendar() }
                    else { AppDelegate.shared?.showSettingsWindow(.calendar) }
                }
                .buttonStyle(FlowButtonStyle())
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 12).frame(height: 40)
        .flowSurface()
        .popover(isPresented: $showingDetails) {
            if let event = vm.upcomingEvent {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Calendar event", systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                    Text(event.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(event.start, format: .dateTime.weekday().day().month().hour().minute())
                    Text("Ends at \(event.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open calendar", action: openCalendar)
                    .buttonStyle(FlowButtonStyle())
                }
                .padding(20).frame(width: 310, alignment: .leading)
            }
        }
        .onChange(of: showingDetails) { _, shown in
            shown ? vm.beginHold() : vm.endHold()
        }
    }

    private func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

struct KeepAwakeControl: View {
    @ObservedObject private var awake = KeepAwakeController.shared
    @State private var showingPresets = false
    var onPopoverChange: (Bool) -> Void = { _ in }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(awake.endsAt == nil ? Theme.textSecondary : Theme.accent)
                if let end = awake.endsAt {
                    Text("Awake for \(max(1, Int(ceil(end.timeIntervalSince(timeline.date) / 60)))) min")
                    Spacer()
                    Button("Stop") { awake.stop() }.buttonStyle(FlowButtonStyle())
                } else {
                    Text("Keep Mac awake")
                    Spacer()
                    Button("Start") { showingPresets = true }
                    .buttonStyle(FlowButtonStyle())
                    .popover(isPresented: $showingPresets) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Keep Mac awake").font(.headline)
                            HStack {
                                ForEach([15, 30, 60, 120], id: \.self) { minutes in
                                    Button("\(minutes) min") {
                                        awake.start(minutes: minutes)
                                        showingPresets = false
                                    }
                                    .buttonStyle(FlowButtonStyle())
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                if let error = awake.error {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        .help(error).accessibilityLabel(error)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .help("Prevents idle sleep until the timer ends. Closing the lid or choosing Sleep still works.")
        }
        .onChange(of: showingPresets) { _, shown in onPopoverChange(shown) }
    }
}
