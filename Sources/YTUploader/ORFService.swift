import Foundation

/// Eine Sendung, deren Beiträge von tv.ORF.at übernommen werden können.
struct ORFShow: Identifiable, Hashable {
    /// Name, wie er im Videotitel erscheinen soll (z. B. „ECO“)
    let label: String
    /// Begriff, nach dem im ORF-Programm gesucht wird (z. B. „Eco“)
    let searchTerm: String

    var id: String { label }

    /// Die Sendungen, die laut Nutzerwunsch zur Auswahl stehen.
    /// `searchTerm` weicht teils vom Anzeigenamen ab, weil das ORF-Programm
    /// eigene Schreibweisen verwendet („Eco“, „Daheim - das Volksgruppenmagazin“).
    static let all: [ORFShow] = [
        ORFShow(label: "Bürgeranwalt", searchTerm: "Bürgeranwalt"),
        ORFShow(label: "Report", searchTerm: "Report"),
        ORFShow(label: "Thema", searchTerm: "Thema"),
        ORFShow(label: "ECO", searchTerm: "Eco"),
        ORFShow(label: "Am Schauplatz", searchTerm: "Am Schauplatz"),
        ORFShow(label: "Am Schauplatz Gericht", searchTerm: "Am Schauplatz Gericht"),
        ORFShow(label: "Daheim", searchTerm: "Daheim"),
        ORFShow(label: "betrifft: uns", searchTerm: "betrifft: uns"),
        ORFShow(label: "WeltWeit", searchTerm: "WeltWeit"),
    ]
}

/// Eine im Tagesprogramm gefundene Ausstrahlung.
struct ORFBroadcast: Identifiable, Hashable {
    let title: String
    let startTime: String     // "17:59"
    let channel: String       // "ORF 2"
    let url: URL

    var id: URL { url }
}

/// Ein einzelner Beitrag innerhalb einer Sendung.
struct ORFItem: Identifiable, Hashable {
    let index: Int
    let title: String
    let text: String

    var id: Int { index }
}

enum ORFError: LocalizedError {
    case dayNotAvailable(String)
    case showNotFound(day: String, aired: [String])
    case noItems
    case network(String)

    var errorDescription: String? {
        switch self {
        case .dayNotAvailable(let day):
            return "Für den \(day) liegt bei tv.ORF.at kein Programm vor. "
                + "Das Archiv reicht nur etwa 30 Tage zurück und wenige Wochen voraus."
        case .showNotFound(let day, let aired):
            let list = aired.prefix(12).joined(separator: ", ")
            return "Am \(day) wurde diese Sendung nicht gefunden.\n\nAn dem Tag lief u. a.: \(list)"
        case .noItems:
            return "Zu dieser Sendung sind auf tv.ORF.at (noch) keine Beitragstexte veröffentlicht."
        case .network(let msg):
            return "tv.ORF.at nicht erreichbar: \(msg)"
        }
    }
}

/// Lädt Sendungsbeschreibungen von tv.ORF.at.
///
/// Ablauf: Tagesprogramm des Senders holen → Ausstrahlung anhand des
/// Sendungsnamens finden → Sendungsseite parsen → Beiträge extrahieren.
enum ORFService {
    private static let channels = [("orf2", "ORF 2"), ("orf1", "ORF 1"), ("orf3", "ORF III")]

    // MARK: - Öffentliche Schnittstelle

    /// Sucht die Ausstrahlungen einer Sendung an einem Datum (alle Sender).
    static func findBroadcasts(show searchTerm: String, on date: Date) async throws -> [ORFBroadcast] {
        let dayLabel = Self.dayFormatter.string(from: date)
        var airedTitles: Set<String> = []
        var anyDayFound = false

        for (slug, display) in channels {
            guard let dayURL = try await dayURL(channel: slug, date: date) else { continue }
            anyDayFound = true
            let all = try await broadcasts(dayURL: dayURL, channel: slug, display: display)
            airedTitles.formUnion(all.map(\.title))
            let hits = match(all, searchTerm: searchTerm)
            if !hits.isEmpty { return hits }
        }

        if !anyDayFound { throw ORFError.dayNotAvailable(dayLabel) }
        throw ORFError.showNotFound(day: dayLabel, aired: airedTitles.sorted())
    }

    /// Extrahiert die Beiträge einer Sendungsseite.
    static func items(at url: URL) async throws -> [ORFItem] {
        let html = try await fetch(url)
        let items = parseItems(html: html)
        if items.isEmpty { throw ORFError.noItems }
        return items
    }

    /// Videotitel aus Beitragstitel + „| Sendung Datum“.
    /// YouTube erlaubt 100 Zeichen – der Zusatz bleibt erhalten, notfalls
    /// wird der Beitragstitel gekürzt.
    static func composedTitle(item: String, show: String, date: Date) -> String {
        let suffix = " | \(show) \(dayFormatter.string(from: date))"
        let room = 100 - suffix.count
        guard room > 1 else { return String(suffix.dropFirst(3).prefix(100)) }
        let head = item.count <= room ? item : String(item.prefix(room - 1)) + "…"
        return head + suffix
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_AT")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    // MARK: - Tagesprogramm

    /// Die Tagesseiten tragen einen Hash im Namen und lassen sich nicht
    /// konstruieren – deshalb den Link aus der Tagesnavigation der Senderseite lesen.
    private static func dayURL(channel: String, date: Date) async throws -> URL? {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.day, .month, .year], from: date)
        guard let d = c.day, let m = c.month, let y = c.year else { return nil }

        guard let indexURL = URL(string: "https://tv.orf.at/program/\(channel)/") else { return nil }
        let html = try await fetch(indexURL)

        let pattern = "href=\"(/program/\(channel)/index~_day-"
            + String(format: "%02d-%02d-%04d", d, m, y)
            + "_-[0-9a-f]+\\.html)\""
        guard let path = firstMatch(pattern, in: html, group: 1) else { return nil }
        return URL(string: "https://tv.orf.at" + path)
    }

    private static func broadcasts(dayURL: URL, channel: String, display: String) async throws -> [ORFBroadcast] {
        let html = try await fetch(dayURL)
        var result: [ORFBroadcast] = []

        // Jede Ausstrahlung ist ein <li …class="broadcast"…>. Die gerade laufende
        // Sendung trägt zusätzlich id="current-broadcast" vor der Klasse.
        for block in html.components(separatedBy: "<li").dropFirst() {
            let head = String(block.prefix(200))
            guard head.contains("class=\"broadcast\"") else { continue }
            guard let start = firstMatch("data-start-time=\"([^\"]+)\"", in: block, group: 1),
                  let href = firstMatch(
                      "<div class=\"series-title\"[^>]*>\\s*<a href=\"([^\"]+)\"", in: block, group: 1),
                  let rawTitle = firstMatch(
                      "<div class=\"series-title\"[^>]*>\\s*<a[^>]*>(.*?)</a>", in: block, group: 1),
                  let url = URL(string: "https://tv.orf.at/program/\(channel)/" + href)
            else { continue }

            let time = start.count >= 16 ? String(start.dropFirst(11).prefix(5)) : ""
            result.append(ORFBroadcast(title: plainText(rawTitle), startTime: time,
                                       channel: display, url: url))
        }
        return result
    }

    /// Zuerst exakte Titel, dann Titelanfang, dann enthaltene Treffer –
    /// so gewinnt „Am Schauplatz“ gegen „Am Schauplatz Gericht“.
    private static func match(_ all: [ORFBroadcast], searchTerm: String) -> [ORFBroadcast] {
        let needle = normalized(searchTerm)
        guard !needle.isEmpty else { return [] }
        let tests: [(String) -> Bool] = [
            { $0 == needle }, { $0.hasPrefix(needle) }, { $0.contains(needle) },
        ]
        for test in tests {
            let hits = all.filter { test(normalized($0.title)) }
            if !hits.isEmpty {
                // Wiederholungen zeigen auf dieselbe Seite – nur einmal anbieten.
                var seen = Set<URL>()
                return hits.filter { seen.insert($0.url).inserted }
            }
        }
        return []
    }

    /// Kleinschreibung ohne Umlaute und Satzzeichen, damit „betrifft: uns“
    /// auch „betrifft: uns - Reportagen ohne Filter“ trifft.
    private static func normalized(_ s: String) -> String {
        var t = s.lowercased()
        for (a, b) in [("ä", "a"), ("ö", "o"), ("ü", "u"), ("ß", "ss")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_AT"))
        let kept = t.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    // MARK: - Beiträge einer Sendungsseite

    static func parseItems(html: String) -> [ORFItem] {
        guard let contentRange = html.range(of: "<div class=\"document-content\">") else { return [] }
        let tail = String(html[contentRange.upperBound...])
        let end = tail.range(of: "<div class=\"broadcast-links\"")
            ?? tail.range(of: "<div class=\"broadcast-staff\"")
        var segment = end.map { String(tail[..<$0.lowerBound]) } ?? tail
        segment = removeBlocks("<figure", "</figure>", in: segment)
        segment = removeBlocks("<script", "</script>", in: segment)

        var items: [ORFItem] = []
        let headings = matches("<h2[^>]*>(.*?)</h2>", in: segment)

        for (i, h) in headings.enumerated() {
            let title = plainText(h.groups[0])
            let bodyStart = h.range.upperBound
            let bodyEnd = i + 1 < headings.count ? headings[i + 1].range.lowerBound : segment.endIndex
            guard bodyStart <= bodyEnd else { continue }
            let body = String(segment[bodyStart..<bodyEnd])

            // Leere Überschrift oder Infobox (z. B. Porträt eines Volksanwalts)
            guard !title.isEmpty,
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<div class=\"fact\"")
            else { continue }

            let text = paragraphs(in: body)
            if !text.isEmpty {
                items.append(ORFItem(index: items.count + 1, title: title, text: text))
            }
        }

        // Einzelthemen-Sendung (Reportage, Doku): kein <h2>, Titel steht in den Metadaten.
        if items.isEmpty {
            let text = paragraphs(in: segment)
            if !text.isEmpty {
                let title = firstMatch("class=\"broadcast-episode-title\"[^>]*>(.*?)</", in: html, group: 1)
                    ?? firstMatch("class=\"broadcast-series-title\"[^>]*>(.*?)</", in: html, group: 1)
                    ?? ""
                items.append(ORFItem(index: 1, title: plainText(title), text: text))
            }
        }
        return items
    }

    private static func paragraphs(in html: String) -> String {
        matches("<p[^>]*>(.*?)</p>", in: html)
            .map { plainText($0.groups[0]) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Netzwerk

    private static func fetch(_ url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                throw ORFError.network("HTTP \(http.statusCode)")
            }
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
        } catch let error as ORFError {
            throw error
        } catch {
            throw ORFError.network(error.localizedDescription)
        }
    }

    // MARK: - HTML-Hilfen

    private struct Match {
        let range: Range<String.Index>
        let groups: [String]
    }

    private static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let r = Range(m.range, in: text) else { return nil }
            var groups: [String] = []
            for i in 1..<m.numberOfRanges {
                groups.append(m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)))
            }
            return Match(range: r, groups: groups)
        }
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let m = matches(pattern, in: text).first, m.groups.count >= group else { return nil }
        return m.groups[group - 1]
    }

    private static func removeBlocks(_ open: String, _ close: String, in text: String) -> String {
        var out = text
        while let s = out.range(of: open), let e = out.range(of: close, range: s.upperBound..<out.endIndex) {
            out.removeSubrange(s.lowerBound..<e.upperBound)
        }
        return out
    }

    /// Tags entfernen, Entities auflösen, Leerraum normalisieren.
    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü",
        "szlig": "ß", "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç",
        "ndash": "–", "mdash": "—", "hellip": "…", "shy": "", "middot": "·", "bull": "•",
        "laquo": "«", "raquo": "»", "bdquo": "„", "ldquo": "“", "rdquo": "”",
        "sbquo": "‚", "lsquo": "‘", "rsquo": "’", "deg": "°", "euro": "€",
        "copy": "©", "reg": "®", "trade": "™", "times": "×", "minus": "−",
    ]

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest.index(after: amp)
            guard let semi = rest[after...].firstIndex(of: ";"),
                  rest.distance(from: after, to: semi) <= 8 else {
                out.append("&")
                rest = rest[after...]
                continue
            }
            let body = String(rest[after..<semi])
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let value: UInt32? = digits.hasPrefix("x") || digits.hasPrefix("X")
                    ? UInt32(digits.dropFirst(), radix: 16)
                    : UInt32(digits)
                if let v = value, let scalar = Unicode.Scalar(v) {
                    out.append(Character(scalar))
                } else {
                    out += "&\(body);"
                }
            } else if let replacement = namedEntities[body] {
                out += replacement
            } else {
                out += "&\(body);"
            }
            rest = rest[rest.index(after: semi)...]
        }
        out += rest
        return out
    }
}
