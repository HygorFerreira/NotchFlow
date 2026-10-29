import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfFile: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

@MainActor
final class FileShelf: ObservableObject {
    @Published private(set) var files: [ShelfFile] = []
    @Published private(set) var busy = false
    @Published var error: String?
    let directory: URL
    private let worker = DispatchQueue(label: "dev.oprimo.NotchFlow.file-shelf", qos: .utility)
    private var pendingURLs: [URL] = []

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/FileShelf", isDirectory: true)
        reload()
    }

    func reload() {
        do {
            guard FileManager.default.fileExists(atPath: directory.path) else { files = []; return }
            let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            files = try folders.flatMap { folder in
                try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
                    .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                    .map { ShelfFile(url: $0) }
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { self.error = String(localized: "The file shelf could not be read.") }
    }

    func pickFiles(onFinish: @escaping () -> Void = {}) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            if response == .OK { self?.importFiles(panel.urls) }
            onFinish()
        }
    }

    func accept(_ providers: [NSItemProvider]) -> Bool {
        let matches = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in matches {
            provider.loadObject(ofClass: NSURL.self) { [weak self] item, _ in
                let url = item as? URL
                if let url { DispatchQueue.main.async { self?.importFiles([url]) } }
            }
        }
        return !matches.isEmpty
    }

    func importFiles(_ urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        guard !busy else { return }
        let urls = pendingURLs
        pendingURLs = []
        guard !urls.isEmpty else { return }
        busy = true
        error = nil
        let directory = directory
        worker.async { [weak self] in
            var failed = false
            let fm = FileManager.default
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard url.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
                          let size = values.fileSize, size <= 200_000_000 else { failed = true; continue }
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                    let existing = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                    guard existing.count < 20 else { failed = true; continue }
                    let id = UUID().uuidString
                    let folder = directory.appendingPathComponent(".import-" + id, isDirectory: true)
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    do {
                        try fm.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
                        try fm.moveItem(at: folder, to: directory.appendingPathComponent(id, isDirectory: true))
                    }
                    catch { try? fm.removeItem(at: folder); throw error }
                } catch { failed = true }
            }
            let hadFailure = failed
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.reload()
                if hadFailure { self.error = String(localized: "Some files could not be added. Choose up to 20 regular files, at most 200 MB each.") }
                if !self.pendingURLs.isEmpty { self.importFiles([]) }
            }
        }
    }

    func remove(_ file: ShelfFile) {
        do {
            try FileManager.default.trashItem(at: file.url.deletingLastPathComponent(), resultingItemURL: nil)
            reload()
        } catch { self.error = String(localized: "The copy could not be moved to Trash.") }
    }
}
