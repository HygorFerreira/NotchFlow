import AppKit
import Combine

@MainActor
final class MusicMonitor: ObservableObject {
    @Published private(set) var playback: MusicPlayback?
    @Published private(set) var enabled: Bool
    @Published private(set) var player: MusicPlayer
    @Published private(set) var status: Status = .disabled
    @Published private(set) var busy = false
    lazy var lyrics = LyricsMonitor(defaults: defaults)

    enum Status { case disabled, waiting, permission, unavailable, ready }
    private let defaults: UserDefaults
    private let worker = DispatchQueue(label: "dev.oprimo.NotchFlow.music", qos: .utility)
    private var timer: AnyCancellable?
    private var generation = 0
    private var inFlight = false
    private var demoMode = false

    init(defaults: UserDefaults = .standard, start: Bool = true) {
        self.defaults = defaults
        player = MusicPlayer(rawValue: defaults.string(forKey: "music.player") ?? "") ?? .spotify
        enabled = defaults.bool(forKey: "music.enabled")
        if start {
            timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.refresh() }
            refresh()
        }
    }

    var hasActivity: Bool { enabled && playback?.isPlaying == true }

    func select(_ value: MusicPlayer) {
        guard player != value else { return }
        generation += 1
        player = value
        defaults.set(value.rawValue, forKey: "music.player")
        playback = nil
        status = enabled ? .waiting : .disabled
        refresh()
    }

    func setEnabled(_ value: Bool) {
        generation += 1
        enabled = value
        defaults.set(value, forKey: "music.enabled")
        playback = nil
        status = value ? .waiting : .disabled
        if value { refresh(prompt: true) }
    }

    func refresh(prompt: Bool = false) {
        guard enabled, !inFlight, !demoMode else { return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).first else {
            playback = nil
            status = .waiting
            return
        }
        inFlight = true
        let request = generation
        let selected = player
        let previous = playback
        let pid = app.processIdentifier
        worker.async { [weak self] in
            let permission = MusicAutomation.permission(pid: pid, prompt: prompt)
            let result: Result<MusicPlayback?, Error> = permission == noErr
                ? Result { try MusicAutomation.read(pid: pid, player: selected, previous: previous) }
                : .failure(MusicAutomation.Failure(code: Int(permission)))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight = false
                guard self.generation == request, self.enabled else { return }
                switch result {
                case .success(let playback): self.playback = playback; self.status = .ready
                case .failure(let error):
                    self.playback = nil
                    let code = (error as? MusicAutomation.Failure)?.code ?? (error as NSError).code
                    self.status = [-1743, -1744].contains(code) ? .permission : .unavailable
                }
            }
        }
    }

    enum Command { case toggle, next, previous, seek(Double) }
    func perform(_ command: Command) {
        guard enabled, playback != nil, !busy, !demoMode,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).first else { return }
        busy = true
        let request = generation
        let selected = player
        let pid = app.processIdentifier
        worker.async { [weak self] in
            let result = Result {
                switch command {
                case .toggle: _ = try MusicAutomation.send(pid: pid, suite: selected.eventSuite, command: "PlPs")
                case .next: _ = try MusicAutomation.send(pid: pid, suite: selected.eventSuite, command: "Next")
                case .previous: _ = try MusicAutomation.send(pid: pid, suite: selected.eventSuite, command: "Prev")
                case .seek(let seconds):
                    guard seconds.isFinite else { return }
                    _ = try MusicAutomation.send(pid: pid, command: "setd", direct: MusicAutomation.property("pPos"),
                                                 value: NSAppleEventDescriptor(double: max(0, seconds)))
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.generation == request else { return }
                if case .failure = result { self.status = .unavailable; self.playback = nil }
                else { self.refresh() }
            }
        }
    }

    func openPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    #if DEBUG
    func setDemo(_ playback: MusicPlayback?) {
        timer?.cancel()
        demoMode = true
        enabled = true
        self.playback = playback
        status = .ready
    }
    #endif
}
