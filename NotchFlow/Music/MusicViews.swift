import SwiftUI

struct MusicArtwork: View {
    let playback: MusicPlayback?
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let data = playback?.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let url = playback?.artworkURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                    placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 40 ? 14 : 5))
        .overlay(RoundedRectangle(cornerRadius: size > 40 ? 14 : 5).strokeBorder(.white.opacity(0.10)))
        .accessibilityHidden(true)
    }
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08))
            .overlay { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.55)) }
    }
}

struct MusicTransport: View {
    @ObservedObject var monitor: MusicMonitor
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 14 : 18) {
            control("backward.end.fill", label: "Previous track") { monitor.perform(.previous) }
            control(monitor.playback?.isPlaying == true ? "pause.fill" : "play.fill",
                    label: monitor.playback?.isPlaying == true ? "Pause music" : "Play music", primary: true) { monitor.perform(.toggle) }
            control("forward.end.fill", label: "Next track") { monitor.perform(.next) }
        }
        .disabled(monitor.busy || monitor.playback == nil)
    }
    private func control(_ symbol: String, label: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: compact ? 13 : 18, weight: .semibold))
                .frame(width: compact ? 26 : primary ? 42 : 32, height: compact ? 28 : primary ? 42 : 32)
                .background(primary && !compact ? Color.white : .clear, in: Circle())
                .foregroundStyle(primary && !compact ? NotchPalette.background : .white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .accessibilityLabel(Text(label.localized)).help(label.localized)
    }
}

struct MusicPeekView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @ObservedObject var monitor: MusicMonitor
    var body: some View {
        HStack(spacing: 12) {
            MusicArtwork(playback: monitor.playback)
            Button { vm.openMusic() } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.playback?.title ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(monitor.playback?.artist ?? "").font(.system(size: 10)).foregroundStyle(NotchPalette.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open music".localized)
            MusicTransport(monitor: monitor, compact: true)
            Button {
                vm.musicPeek = false
                vm.expanded = true
            } label: {
                Image(systemName: "square.grid.2x2").frame(width: 24, height: 28)
            }.buttonStyle(.plain).help("Open dashboard".localized).accessibilityLabel(Text("Open dashboard"))
        }
        .foregroundStyle(.white).padding(.horizontal, 18)
        .frame(height: NotchViewModel.musicPeekHeight)
    }
}

struct MusicCompactView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @ObservedObject var monitor: MusicMonitor
    var body: some View {
        HStack(spacing: 0) {
            MusicArtwork(playback: monitor.playback, size: 23)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
            Color.clear.frame(width: vm.notchWidth)
            Image(systemName: "waveform").font(.system(size: 17)).foregroundStyle(Theme.accent)
                .accessibilityLabel(Text("Music playing"))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
        }.frame(height: vm.notchHeight)
    }
}

struct MusicDashboardView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @ObservedObject var monitor: MusicMonitor
    @State private var seekValue: Double?
    @State private var seeking = false
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(MusicPlayer.allCases) { player in
                        Button { monitor.select(player) } label: {
                            Text(player.name).font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 14).frame(height: 28)
                                .foregroundStyle(monitor.player == player ? NotchPalette.text : NotchPalette.secondary)
                                .background(monitor.player == player ? NotchPalette.cardHover : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(FlowCompactButtonStyle())
                            .accessibilityAddTraits(monitor.player == player ? .isSelected : [])
                    }
                }.padding(3).background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Toggle("Music in the notch", isOn: Binding(get: { monitor.enabled }, set: { monitor.setEnabled($0) }))
                    .toggleStyle(.switch).font(.system(size: 11))
            }
            if let playback = monitor.playback {
                HStack(spacing: 24) {
                    MusicArtwork(playback: playback, size: 132)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(playback.isPlaying ? "Now playing" : "Paused", systemImage: playback.isPlaying ? "waveform" : "pause.circle")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent)
                        Text(playback.title).font(.system(size: 19, weight: .semibold)).tracking(-0.4).lineLimit(1).help(playback.title)
                        Text(playback.artist).font(.system(size: 12)).foregroundStyle(NotchPalette.secondary).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 2) {
                                Slider(value: Binding(get: { seekValue ?? playback.elapsed(at: context.date) },
                                                      set: { seekValue = $0 }),
                                       in: 0...max(1, playback.duration), onEditingChanged: { editing in
                                    if editing && !seeking { vm.beginHold() }
                                    if !editing && seeking { vm.endHold() }
                                    seeking = editing
                                    if !editing, let seekValue { monitor.perform(.seek(min(playback.duration, seekValue))); self.seekValue = nil }
                                })
                                .disabled(playback.duration <= 0 || monitor.busy)
                                .accessibilityLabel(Text("Playback position"))
                                HStack {
                                    Text(MusicPlayback.timeLabel(seekValue ?? playback.elapsed(at: context.date)))
                                    Spacer()
                                    Text(MusicPlayback.timeLabel(playback.duration))
                                }.font(.system(size: 10).monospacedDigit()).foregroundStyle(NotchPalette.secondary)
                            }
                        }
                        HStack { Spacer(); MusicTransport(monitor: monitor); Spacer() }
                    }
                }
                .padding(16)
                .background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NotchPalette.border))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "music.note").font(.system(size: 25)).foregroundStyle(NotchPalette.secondary)
                    Text(statusMessage.localized).font(.system(size: 12)).multilineTextAlignment(.center)
                    HStack(spacing: 14) {
                        Button("Open player") { monitor.openPlayer() }
                        if monitor.enabled {
                            Button(monitor.status == .permission ? "Authorize access" : "Refresh music") { monitor.refresh(prompt: true) }
                        }
                    }.buttonStyle(.bordered).font(.system(size: 11))
                }.frame(maxWidth: .infinity, minHeight: 150)
                    .background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 16))
            }
            if monitor.enabled {
                MusicExtrasView(monitor: monitor, lyrics: monitor.lyrics)
            }
        }
        .foregroundStyle(NotchPalette.text)
        .onChange(of: monitor.playback?.id) { _, _ in seekValue = nil }
        .onChange(of: monitor.player) { _, _ in seekValue = nil }
        .onDisappear { if seeking { vm.endHold(); seeking = false } }
    }

    private var statusMessage: String {
        switch monitor.status {
        case .disabled: return "Enable music to show your player in the notch."
        case .waiting: return "Open the selected player and start a song."
        case .permission: return "Allow access to the player in System Settings → Privacy & Security → Automation."
        case .unavailable: return "The player could not be read. Try refreshing music."
        case .ready: return "Nothing playing. Start a song in the selected player."
        }
    }
}
