import Foundation

/// Hält die Upload-Warteschlange und speichert sie als JSON auf der Platte,
/// damit Aufträge einen Neustart der App überleben.
@MainActor
final class QueueStore: ObservableObject {
    @Published var jobs: [UploadJob] = [] {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YTUploader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("queue.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              var loaded = try? JSONDecoder().decode([UploadJob].self, from: data) else { return }
        // Ein beim letzten Beenden aktiver Upload wird als "unterbrochen" markiert.
        for i in loaded.indices where loaded[i].status == .uploading {
            loaded[i].status = .paused
        }
        jobs = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func update(_ job: UploadJob) {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[i] = job
        }
    }

    func remove(_ job: UploadJob) {
        jobs.removeAll { $0.id == job.id }
    }

    /// Nächster Auftrag, der hochgeladen werden soll (in Listenreihenfolge).
    var nextUploadable: UploadJob? {
        jobs.first { $0.status == .pending || $0.status == .paused }
    }
}
