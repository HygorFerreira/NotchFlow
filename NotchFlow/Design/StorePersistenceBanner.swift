import AppKit
import SwiftUI

/// Persistent feedback across windows, including failures triggered by the notch.
struct StorePersistenceBanner: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        if let message = store.persistenceError ?? store.recoveryNotice {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if store.persistenceError != nil && store.canRetrySave {
                    Button("Retry saving") { store.save() }
                }
                Button("Show data folder") {
                    NSWorkspace.shared.open(store.dataFileURL.deletingLastPathComponent())
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
        }
    }
}
