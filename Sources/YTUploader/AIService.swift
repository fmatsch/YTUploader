import Foundation

enum AIError: LocalizedError {
    case missingKey
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Bitte zuerst einen OpenAI-API-Key in den Einstellungen eintragen."
        case .api(let msg):
            return "KI-Anfrage fehlgeschlagen: \(msg)"
        }
    }
}

/// Überarbeitet Titel und Beschreibung per OpenAI-API.
/// Der API-Key wird im Schlüsselbund gespeichert.
@MainActor
final class AIService: ObservableObject {
    @Published var apiKey: String = "" {
        didSet {
            if apiKey.isEmpty {
                Keychain.delete(account: "openai_api_key")
            } else {
                Keychain.save(Data(apiKey.utf8), account: "openai_api_key")
            }
        }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "openaiModel") }
    }

    init() {
        model = UserDefaults.standard.string(forKey: "openaiModel") ?? "gpt-5-mini"
        if let data = Keychain.load(account: "openai_api_key"),
           let key = String(data: data, encoding: .utf8) {
            apiKey = key
        }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    enum Field { case title, description, tags }
    enum Mode { case improve, expand, suggest }

    /// Liefert den überarbeiteten Text für das gewünschte Feld.
    func rewrite(_ field: Field, mode: Mode, title: String, description: String, tags: String = "") async throws -> String {
        guard isConfigured else { throw AIError.missingKey }

        let system = """
        Du bist Experte für YouTube-Metadaten. Antworte ausschließlich mit dem \
        fertigen Text – ohne Anführungszeichen, ohne Erklärungen, ohne Markdown. \
        Antworte in der Sprache des Originaltexts.
        """

        var prompt: String
        switch (field, mode) {
        case (.tags, _):
            prompt = """
            Schlage passende YouTube-Tags für dieses Video vor: 10 bis 15 Tags, \
            als kommagetrennte Liste, ohne #-Zeichen, insgesamt unter 450 Zeichen. \
            Mische allgemeine Suchbegriffe und spezifische Begriffe zum Inhalt.

            Titel: \(title)
            """
            if !description.isEmpty {
                prompt += "\n\nBeschreibung:\n\(description)"
            }
            if !tags.isEmpty {
                prompt += "\n\nBereits vorhandene Tags (übernehmen, sofern passend, und ergänzen): \(tags)"
            }
        case (.title, .improve):
            prompt = "Verbessere den folgenden YouTube-Videotitel: prägnant, ansprechend, neugierig machend, maximal 100 Zeichen.\n\nTitel: \(title)"
        case (.title, .expand):
            prompt = "Erweitere den folgenden YouTube-Videotitel um aussagekräftige Details, maximal 100 Zeichen.\n\nTitel: \(title)"
        case (.description, .improve):
            prompt = "Überarbeite und verbessere die folgende YouTube-Videobeschreibung. Behalte Struktur, Links und Kernaussagen bei.\n\nBeschreibung:\n\(description)"
        case (.description, .expand):
            prompt = "Erweitere die folgende YouTube-Videobeschreibung deutlich: mehr Details, sinnvolle Absätze, bleibe aber beim Inhalt des Originals.\n\nBeschreibung:\n\(description)"
        case (.title, .suggest):
            prompt = "Schlage einen prägnanten, ansprechenden YouTube-Videotitel vor, maximal 100 Zeichen."
        case (.description, .suggest):
            prompt = "Schlage eine passende YouTube-Videobeschreibung vor.\n\nTitel: \(title)"
        }
        // Das jeweils andere Feld als Kontext mitgeben
        switch field {
        case .title where !description.isEmpty:
            prompt += "\n\nZum Kontext die Videobeschreibung:\n\(description)"
        case .description where !title.isEmpty:
            prompt += "\n\nZum Kontext der Videotitel: \(title)"
        default:
            break
        }

        let body = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
        ])

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.api("Unlesbare Antwort.")
        }
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw AIError.api(msg)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.api("Keine Antwort erhalten.")
        }

        var result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Falls das Modell den Text doch in Anführungszeichen setzt
        for quote in ["\"", "„", "“", "»", "«"] {
            if result.hasPrefix(quote) && (result.hasSuffix("\"") || result.hasSuffix("“") || result.hasSuffix("«") || result.hasSuffix("»")) {
                result = String(result.dropFirst(quote.count).dropLast(1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return result
    }
}
