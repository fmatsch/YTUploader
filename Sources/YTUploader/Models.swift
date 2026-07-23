import Foundation

enum JobStatus: String, Codable {
    case pending      // wartet in der Warteschlange
    case uploading    // wird gerade hochgeladen
    case paused       // unterbrochen (z. B. kein Internet), wird fortgesetzt
    case completed    // fertig hochgeladen
    case failed       // dauerhaft fehlgeschlagen

    var label: String {
        switch self {
        case .pending: return "Wartet"
        case .uploading: return "Lädt hoch …"
        case .paused: return "Unterbrochen"
        case .completed: return "Fertig"
        case .failed: return "Fehler"
        }
    }
}

enum Privacy: String, Codable, CaseIterable, Identifiable {
    case publicVideo = "public"
    case unlisted = "unlisted"
    case privateVideo = "private"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .publicVideo: return "Öffentlich"
        case .unlisted: return "Nicht gelistet"
        case .privateVideo: return "Privat"
        }
    }
}

struct Category: Identifiable {
    let id: String
    let label: String

    static let all: [Category] = [
        Category(id: "1", label: "Film & Animation"),
        Category(id: "2", label: "Autos & Fahrzeuge"),
        Category(id: "10", label: "Musik"),
        Category(id: "15", label: "Tiere"),
        Category(id: "17", label: "Sport"),
        Category(id: "19", label: "Reisen & Events"),
        Category(id: "20", label: "Gaming"),
        Category(id: "22", label: "Menschen & Blogs"),
        Category(id: "23", label: "Komödie"),
        Category(id: "24", label: "Unterhaltung"),
        Category(id: "25", label: "Nachrichten & Politik"),
        Category(id: "26", label: "Praktische Tipps & Styling"),
        Category(id: "27", label: "Bildung"),
        Category(id: "28", label: "Wissenschaft & Technik"),
    ]
}

struct UploadJob: Identifiable, Codable, Equatable {
    var id = UUID()
    var videoPath: String
    var thumbnailPath: String?
    var title: String
    var videoDescription: String
    var tags: [String]
    var categoryId: String
    var privacy: Privacy
    /// Wenn gesetzt: Video wird als "privat" hochgeladen und zu diesem
    /// Zeitpunkt von YouTube automatisch veröffentlicht.
    var publishAt: Date?
    var madeForKids: Bool

    var status: JobStatus = .pending
    var errorMessage: String?
    var progress: Double = 0          // 0…1
    var bytesSent: Int64 = 0
    var totalBytes: Int64 = 0
    /// URL der laufenden Resumable-Upload-Session (zum Fortsetzen nach Abbruch)
    var resumableURL: String?
    var videoId: String?
    var thumbnailUploaded: Bool = false

    var videoFileName: String {
        (videoPath as NSString).lastPathComponent
    }
}
