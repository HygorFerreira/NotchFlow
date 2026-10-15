import SwiftUI

/// Collapsed pill. When a focus session is running it shows the countdown in
/// the LEFT ear and the active task in the RIGHT ear, with a hard center gap
/// the exact width of the hardware notch so nothing hides under the camera.
/// When idle it's just the bare notch footprint (invisible).
struct CollapsedTimerView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var focus: FocusTimer

    var body: some View {
        if focus.isActive {
            if vm.store.settings.minimalMode {
                // Minimal: no ears, no text — just reserve the notch footprint
                // (plus the tray room below, drawn in RootNotchView). The pill
                // shrinks to `notchWidth` via NotchViewModel.collapsedWidth.
                VStack(spacing: 0) {
                    Color.clear.frame(height: vm.notchHeight)
                    Spacer(minLength: 0)
                }
            } else {
                fullPill
            }
        } else {
            Color.clear
        }
    }

    private var fullPill: some View {
        VStack(spacing: 0) {
                // ---- ears (flexible so the row always fits the window width;
                //      fixed-width ears would overflow and push the tray sides
                //      off-screen) ----
                HStack(spacing: 0) {
                    // left ear: countdown, pushed toward the notch
                    HStack(spacing: 6) {
                        if focus.state == .paused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(focus.state == .running ? Theme.accent : Theme.textSecondary)
                        }
                        Text(focus.timeLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)

                    // center: the physical notch — must stay empty
                    Color.clear.frame(width: vm.notchWidth)

                    // right ear: active task title
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus.activeTask?.title ?? "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        if vm.store.settings.showTimeline && !vm.store.settings.rainbowTimeline {
                            FlowProgressBar(value: focus.progress, height: 3, color: NotchPalette.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                    .padding(.trailing, 16)
                }
                .frame(maxWidth: .infinity)
                .frame(height: vm.notchHeight)

                // Progress lives in the accent tray (drawn in RootNotchView);
                // this spacer just reserves the room below the notch line.
                Spacer(minLength: 0)
            }
    }
}
