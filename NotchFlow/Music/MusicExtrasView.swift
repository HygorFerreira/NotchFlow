import SwiftUI

struct MusicExtrasView: View {
    @ObservedObject var monitor: MusicMonitor
    @ObservedObject var lyrics: LyricsMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.quote").foregroundStyle(Theme.accent)
                Toggle("Synced lyrics", isOn: Binding(get: { lyrics.enabled }, set: { lyrics.setEnabled($0, playback: monitor.playback) }))
                    .toggleStyle(.switch).font(.system(size: 11, weight: .medium))
            }
            if lyrics.enabled {
                lyricsBody.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Lyrics sends the song title, artist, album and duration to LRCLIB when enabled.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12).background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(NotchPalette.border))
        .onAppear { lyrics.update(monitor.playback) }
        .onChange(of: monitor.playback?.id) { _, _ in lyrics.update(monitor.playback) }
        .onChange(of: monitor.player) { _, _ in lyrics.update(monitor.playback, force: true) }
        .onDisappear { lyrics.update(nil) }
    }
    @ViewBuilder private var lyricsBody: some View {
        if lyrics.status == .loading { ProgressView().controlSize(.small) }
        else if !lyrics.lines.isEmpty, let playback = monitor.playback {
            TimelineView(.periodic(from: .now, by: 0.3)) { context in
                let active = SyncedLyrics.activeLine(in: lyrics.lines, at: playback.elapsed(at: context.date))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(lyrics.lines) { line in
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: 12, weight: active == line.id ? .semibold : .regular))
                                    .foregroundStyle(active == line.id ? NotchPalette.text : NotchPalette.secondary)
                                    .id(line.id)
                            }
                        }
                    }.frame(height: 70)
                        .onChange(of: active, initial: true) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        } else if let plain = lyrics.plainLyrics, !plain.isEmpty {
            ScrollView { Text(plain).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 70)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(lyrics.status == .instrumental ? "Instrumental track" : lyrics.status == .failed ? "Lyrics could not be loaded" : "No lyrics available")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if lyrics.status == .failed { Button("Try again") { lyrics.update(monitor.playback, force: true) }.font(.system(size: 10)) }
            }
        }
    }
}
