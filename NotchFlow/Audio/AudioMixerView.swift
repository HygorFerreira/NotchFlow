import SwiftUI
import CoreAudio

@available(macOS 14.2, *)
@MainActor
final class AudioMixerModel: ObservableObject {
    static let shared = AudioMixerModel()
    struct Source: Identifiable {
        let id: AudioObjectID
        let pid: pid_t
        let name: String
        let icon: NSImage?
        var volume: Double = 1
        var muted = false
    }
    @Published private(set) var enabled = false
    @Published private(set) var sources: [Source] = []
    @Published private(set) var error: String?
    private var routes: [AudioObjectID: AudioMixerRoute] = [:]
    private var timer: Timer?

    func setEnabled(_ value: Bool) {
        stop()
        error = nil
        guard value else { return }
        enabled = true
        refresh()
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.refresh() }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        routes.values.forEach { $0.stop() }
        routes.removeAll()
        sources = []
        enabled = false
    }
    func refresh() {
        guard enabled else { return }
        do {
            if routes.values.contains(where: { !$0.isOutputCurrent() }) {
                stop()
                error = String(localized: "Audio output changed. The original sound was restored. Enable the mixer again.")
                return
            }
            let objects = try MixerHAL.list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            var next: [Source] = []
            for object in objects {
                guard let pid = try? MixerHAL.read(object, kAudioProcessPropertyPID, initial: pid_t(0)),
                      pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { continue }
                let old = sources.first { $0.id == object && $0.pid == pid }
                let active = (try? MixerHAL.read(object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) == 1
                guard active || old != nil else { continue }
                if let old { next.append(old); continue }
                let app = NSRunningApplication(processIdentifier: pid)
                let bundle: CFString? = try? MixerHAL.read(object, kAudioProcessPropertyBundleID, initial: "" as CFString)
                let name = app?.localizedName ?? (bundle as String?).flatMap { $0.isEmpty ? nil : $0 } ?? "Audio · \(pid)"
                next.append(Source(id: object, pid: pid, name: name, icon: app?.icon))
            }
            let removed = routes.keys.filter { id in !next.contains { $0.id == id && $0.pid == sources.first(where: { $0.id == id })?.pid } }
            for id in removed { routes.removeValue(forKey: id)?.stop() }
            sources = next.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            stop()
            self.error = String(localized: "Could not read audio sources.") + " " + error.localizedDescription
        }
    }
    func setVolume(_ id: AudioObjectID, volume: Double? = nil, muted: Bool? = nil) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var source = sources[index]
        if let volume, volume.isFinite { source.volume = min(1, max(0, volume)) }
        if let muted { source.muted = muted }
        let level = Float(source.muted ? 0 : source.volume)
        do {
            if level == 1 {
                routes.removeValue(forKey: id)?.stop()
            } else if let route = routes[id] {
                route.setVolume(level)
            } else {
                // Confirm process identity before taking over its output.
                let pid = try MixerHAL.read(id, kAudioProcessPropertyPID, initial: pid_t(0))
                guard pid == source.pid else { refresh(); return }
                routes[id] = try AudioMixerRoute(process: id, output: MixerHAL.defaultOutput(), volume: level)
            }
            sources[index] = source
            error = nil
        } catch {
            routes.removeValue(forKey: id)?.stop()
            sources[index].volume = 1
            sources[index].muted = false
            self.error = String(localized: "Could not control this source. Allow system audio recording in System Settings and try again.") + " " + error.localizedDescription
        }
    }
}

struct AudioMixerView: View {
    var body: some View {
        if #available(macOS 14.2, *) {
            AvailableAudioMixerView(model: .shared)
        } else {
            Text("The audio mixer requires macOS 14.2 or later.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@available(macOS 14.2, *)
private struct AvailableAudioMixerView: View {
    @ObservedObject var model: AudioMixerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.accent)
                Toggle("Audio mixer", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                    .toggleStyle(.switch).font(.system(size: 12, weight: .medium))
            }.padding(10).background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Control each audio process. Windows and tabs from the same app may share a volume control.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = model.error {
                        Text(error).font(.caption).foregroundStyle(Theme.danger).textSelection(.enabled)
                    }
                    if !model.enabled {
                        FlowEmptyState(symbol: "speaker.wave.2", title: "Sound, your way",
                            detail: "Enable the mixer, play audio in an app, then adjust its volume. macOS may request access to system audio. Audio is processed locally and is not recorded.")
                    } else if model.sources.isEmpty {
                        FlowEmptyState(symbol: "waveform", title: "Ready to listen",
                            detail: "Play audio in an app to see it here.")
                    }
                    ForEach(model.sources) { source in
                        HStack(spacing: 8) {
                            if let icon = source.icon {
                                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                            } else { Image(systemName: "app.fill").frame(width: 24) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }.frame(width: 110, alignment: .leading)
                            Button { model.setVolume(source.id, muted: !source.muted) } label: {
                                Image(systemName: source.muted || source.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            }.buttonStyle(FlowCompactButtonStyle(selected: source.muted))
                                .accessibilityLabel(Text(source.muted ? "Unmute audio" : "Mute audio"))
                                .help(source.muted ? "Unmute audio".localized : "Mute audio".localized)
                            Slider(value: Binding(get: { source.volume }, set: { model.setVolume(source.id, volume: $0) }), in: 0...1)
                                .disabled(source.muted).accessibilityLabel(Text("Volume: \(source.name)"))
                            Text("\(Int((source.muted ? 0 : source.volume) * 100))%")
                                .monospacedDigit().font(.system(size: 10)).frame(width: 34, alignment: .trailing)
                        }.padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                    }
                }
            }
        }
    }
}
