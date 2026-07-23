import Foundation
import Network

enum UploadError: LocalizedError {
    case fileNotFound(String)
    case api(String)
    case sessionExpired
    case offline

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "Datei nicht gefunden: \(path)"
        case .api(let msg): return msg
        case .sessionExpired: return "Upload-Session abgelaufen, wird neu gestartet."
        case .offline: return "Keine Internetverbindung."
        }
    }
}

/// Arbeitet die Warteschlange seriell ab: ein Video nach dem anderen,
/// per YouTube-Resumable-Upload. Bei Verbindungsabbruch wird pausiert und
/// automatisch an der letzten bestätigten Position fortgesetzt.
@MainActor
final class UploadManager: ObservableObject {
    @Published var isRunning = false
    @Published var isOnline = true

    private let store: QueueStore
    private let auth: AuthManager
    private var worker: Task<Void, Never>?
    private let monitor = NWPathMonitor()

    /// 8 MB pro Chunk – muss ein Vielfaches von 256 KB sein.
    private let chunkSize = 8 * 1024 * 1024

    init(store: QueueStore, auth: AuthManager) {
        self.store = store
        self.auth = auth
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                let cameBack = online && !self.isOnline
                self.isOnline = online
                // Internet wieder da → Warteschlange automatisch fortsetzen
                if cameBack && self.isRunning && self.worker == nil {
                    self.startWorker()
                }
            }
        }
        monitor.start(queue: .global())
    }

    func start() {
        guard !isRunning || worker == nil else { return }
        isRunning = true
        startWorker()
    }

    func stop() {
        isRunning = false
        worker?.cancel()
        worker = nil
        for var job in store.jobs where job.status == .uploading {
            job.status = .paused
            store.update(job)
        }
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.processQueue()
            await MainActor.run { self?.worker = nil }
        }
    }

    private func processQueue() async {
        while isRunning, !Task.isCancelled {
            guard isOnline else { return }   // Netz-Monitor startet uns neu
            guard var job = store.nextUploadable else {
                isRunning = false
                return
            }
            job.status = .uploading
            job.errorMessage = nil
            store.update(job)

            do {
                try await upload(&job)
                job.status = .completed
                job.progress = 1
                store.update(job)
            } catch is CancellationError {
                job.status = .paused
                store.update(job)
                return
            } catch let error as UploadError {
                switch error {
                case .offline:
                    job.status = .paused
                    store.update(job)
                    return
                case .sessionExpired:
                    // Session weg → Fortschritt zurücksetzen, gleich neu versuchen
                    job.resumableURL = nil
                    job.bytesSent = 0
                    job.progress = 0
                    job.status = .pending
                    store.update(job)
                default:
                    job.status = .failed
                    job.errorMessage = error.localizedDescription
                    store.update(job)
                }
            } catch {
                if Self.isConnectivityError(error) {
                    job.status = .paused
                    store.update(job)
                    return
                }
                job.status = .failed
                job.errorMessage = error.localizedDescription
                store.update(job)
            }
        }
    }

    // MARK: - Einzelner Upload

    private func upload(_ job: inout UploadJob) async throws {
        let fileURL = URL(fileURLWithPath: job.videoPath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: job.videoPath),
              let size = attrs[.size] as? Int64 else {
            throw UploadError.fileNotFound(job.videoPath)
        }
        job.totalBytes = size
        store.update(job)

        // 1. Session anlegen oder bestehende fortsetzen
        if let existing = job.resumableURL {
            switch try await queryOffset(sessionURL: existing, totalBytes: size) {
            case .completed(let videoId):
                job.videoId = videoId
                job.bytesSent = size
            case .resumeFrom(let offset):
                job.bytesSent = offset
            case .expired:
                throw UploadError.sessionExpired
            }
        } else {
            job.resumableURL = try await initiateSession(job: job, totalBytes: size)
            job.bytesSent = 0
        }
        store.update(job)

        // 2. Chunks hochladen
        if job.videoId == nil {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            while job.bytesSent < size {
                try Task.checkCancellation()
                guard isOnline else { throw UploadError.offline }

                try handle.seek(toOffset: UInt64(job.bytesSent))
                let chunk = try handle.read(upToCount: min(chunkSize, Int(size - job.bytesSent))) ?? Data()
                guard !chunk.isEmpty else { break }

                let result = try await uploadChunk(
                    sessionURL: job.resumableURL!,
                    chunk: chunk,
                    offset: job.bytesSent,
                    totalBytes: size
                )
                switch result {
                case .completed(let videoId):
                    job.videoId = videoId
                    job.bytesSent = size
                case .resumeFrom(let offset):
                    job.bytesSent = offset
                case .expired:
                    throw UploadError.sessionExpired
                }
                job.progress = Double(job.bytesSent) / Double(size)
                store.update(job)
            }
        }

        guard job.videoId != nil else {
            throw UploadError.api("Upload beendet, aber keine Video-ID erhalten.")
        }

        // 3. Thumbnail setzen
        if let thumbPath = job.thumbnailPath, !job.thumbnailUploaded {
            try await uploadThumbnail(videoId: job.videoId!, path: thumbPath)
            job.thumbnailUploaded = true
            store.update(job)
        }
    }

    private enum ChunkResult {
        case completed(videoId: String)
        case resumeFrom(Int64)
        case expired
    }

    private func initiateSession(job: UploadJob, totalBytes: Int64) async throws -> String {
        let token = try await auth.validAccessToken()

        var snippet: [String: Any] = [
            "title": job.title,
            "description": job.videoDescription,
            "categoryId": job.categoryId,
        ]
        if !job.tags.isEmpty { snippet["tags"] = job.tags }

        var status: [String: Any] = [
            "selfDeclaredMadeForKids": job.madeForKids,
        ]
        if let publishAt = job.publishAt {
            // Geplante Veröffentlichung: privat hochladen, YouTube schaltet
            // zum angegebenen Zeitpunkt automatisch auf öffentlich.
            status["privacyStatus"] = "private"
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            status["publishAt"] = fmt.string(from: publishAt)
        } else {
            status["privacyStatus"] = job.privacy.rawValue
        }

        let body = try JSONSerialization.data(withJSONObject: [
            "snippet": snippet,
            "status": status,
        ])

        var req = URLRequest(url: URL(string:
            "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(String(totalBytes), forHTTPHeaderField: "X-Upload-Content-Length")
        req.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UploadError.api("Keine Antwort.") }
        guard http.statusCode == 200,
              let location = http.value(forHTTPHeaderField: "Location") else {
            throw UploadError.api(Self.apiErrorMessage(data: data, status: http.statusCode))
        }
        return location
    }

    private func uploadChunk(sessionURL: String, chunk: Data, offset: Int64, totalBytes: Int64) async throws -> ChunkResult {
        let token = try await auth.validAccessToken()
        var req = URLRequest(url: URL(string: sessionURL)!)
        req.httpMethod = "PUT"
        req.timeoutInterval = 300
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let last = offset + Int64(chunk.count) - 1
        req.setValue("bytes \(offset)-\(last)/\(totalBytes)", forHTTPHeaderField: "Content-Range")

        let (data, resp) = try await URLSession.shared.upload(for: req, from: chunk)
        return try Self.parseSessionResponse(data: data, resp: resp, fallbackOffset: offset)
    }

    /// Fragt bei einer bestehenden Session nach, wie viele Bytes schon angekommen sind.
    private func queryOffset(sessionURL: String, totalBytes: Int64) async throws -> ChunkResult {
        let token = try await auth.validAccessToken()
        var req = URLRequest(url: URL(string: sessionURL)!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("bytes */\(totalBytes)", forHTTPHeaderField: "Content-Range")

        let (data, resp) = try await URLSession.shared.upload(for: req, from: Data())
        return try Self.parseSessionResponse(data: data, resp: resp, fallbackOffset: 0)
    }

    private static func parseSessionResponse(data: Data, resp: URLResponse, fallbackOffset: Int64) throws -> ChunkResult {
        guard let http = resp as? HTTPURLResponse else { throw UploadError.api("Keine Antwort.") }
        switch http.statusCode {
        case 200, 201:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                throw UploadError.api("Video hochgeladen, aber Antwort unlesbar.")
            }
            return .completed(videoId: id)
        case 308:
            // "Range: bytes=0-524287" → nächstes Byte ist 524288
            if let range = http.value(forHTTPHeaderField: "Range"),
               let dash = range.lastIndex(of: "-"),
               let lastByte = Int64(range[range.index(after: dash)...]) {
                return .resumeFrom(lastByte + 1)
            }
            return .resumeFrom(fallbackOffset)
        case 404, 410:
            return .expired
        default:
            throw UploadError.api(apiErrorMessage(data: data, status: http.statusCode))
        }
    }

    private func uploadThumbnail(videoId: String, path: String) async throws {
        guard let imageData = FileManager.default.contents(atPath: path) else {
            throw UploadError.fileNotFound(path)
        }
        let token = try await auth.validAccessToken()
        let contentType = path.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"

        var req = URLRequest(url: URL(string:
            "https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=\(videoId)&uploadType=media")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.upload(for: req, from: imageData)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw UploadError.api("Thumbnail fehlgeschlagen: " + Self.apiErrorMessage(data: data, status: status))
        }
    }

    private static func apiErrorMessage(data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            if let errors = error["errors"] as? [[String: Any]],
               let reason = errors.first?["reason"] as? String {
                return "\(message) (\(reason))"
            }
            return message
        }
        return "YouTube-API-Fehler (HTTP \(status))"
    }

    private static func isConnectivityError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed:
            return true
        default:
            return false
        }
    }
}
