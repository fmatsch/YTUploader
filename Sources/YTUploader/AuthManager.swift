import Foundation
import AppKit
import Network
import CryptoKit

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date
}

enum AuthError: LocalizedError {
    case missingCredentials
    case flowFailed(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Bitte zuerst Client-ID und Client-Secret in den Einstellungen eintragen."
        case .flowFailed(let msg):
            return "Anmeldung fehlgeschlagen: \(msg)"
        case .notSignedIn:
            return "Nicht bei YouTube angemeldet."
        }
    }
}

/// Google-OAuth für Desktop-Apps: öffnet den Browser, empfängt den
/// Autorisierungscode über einen lokalen Loopback-Server (127.0.0.1)
/// und tauscht ihn gegen Access-/Refresh-Token (mit PKCE).
@MainActor
final class AuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var channelName: String?

    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: "clientID") }
    }
    @Published var clientSecret: String {
        didSet { UserDefaults.standard.set(clientSecret, forKey: "clientSecret") }
    }

    private var tokens: OAuthTokens? {
        didSet {
            if let tokens, let data = try? JSONEncoder().encode(tokens) {
                Keychain.save(data, account: "oauth_tokens")
            } else if tokens == nil {
                Keychain.delete(account: "oauth_tokens")
            }
            isSignedIn = tokens != nil
        }
    }

    init() {
        clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
        clientSecret = UserDefaults.standard.string(forKey: "clientSecret") ?? ""
        channelName = UserDefaults.standard.string(forKey: "channelName")
        if let data = Keychain.load(account: "oauth_tokens"),
           let stored = try? JSONDecoder().decode(OAuthTokens.self, from: data) {
            tokens = stored
            isSignedIn = true
        }
    }

    func signOut() {
        tokens = nil
        channelName = nil
        UserDefaults.standard.removeObject(forKey: "channelName")
    }

    // MARK: - Anmeldung

    func signIn() async throws {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw AuthError.missingCredentials
        }

        // PKCE
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let server = LoopbackServer()
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        NSWorkspace.shared.open(comps.url!)

        let code = try await server.waitForCode()
        server.stop()

        let body = Self.formEncode([
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        let json = try await Self.tokenRequest(body: body)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expires = json["expires_in"] as? Double else {
            throw AuthError.flowFailed("Unerwartete Antwort vom Token-Endpunkt.")
        }
        tokens = OAuthTokens(
            accessToken: access,
            refreshToken: refresh,
            expiry: Date().addingTimeInterval(expires - 60)
        )
        await fetchChannelName()
    }

    /// Liefert ein gültiges Access-Token, erneuert es bei Bedarf.
    func validAccessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notSignedIn }
        if current.expiry > Date() { return current.accessToken }

        let body = Self.formEncode([
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": current.refreshToken,
            "grant_type": "refresh_token",
        ])
        let json = try await Self.tokenRequest(body: body)
        guard let access = json["access_token"] as? String,
              let expires = json["expires_in"] as? Double else {
            // Refresh-Token ungültig geworden → Neuanmeldung nötig
            tokens = nil
            throw AuthError.notSignedIn
        }
        var updated = current
        updated.accessToken = access
        updated.expiry = Date().addingTimeInterval(expires - 60)
        tokens = updated
        return access
    }

    private func fetchChannelName() async {
        guard let token = try? await validAccessToken() else { return }
        var req = URLRequest(url: URL(string:
            "https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let snippet = items.first?["snippet"] as? [String: Any],
              let title = snippet["title"] as? String else { return }
        channelName = title
        UserDefaults.standard.set(title, forKey: "channelName")
    }

    // MARK: - Hilfen

    private static func tokenRequest(body: Data) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.flowFailed("Ungültige Antwort.")
        }
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let desc = (json["error_description"] as? String)
                ?? (json["error"] as? String) ?? "HTTP \(http.statusCode)"
            throw AuthError.flowFailed(desc)
        }
        return json
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let s = params.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        return Data(s.utf8)
    }

    private static func randomURLSafeString(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

/// Winziger HTTP-Server auf 127.0.0.1, der genau eine Anfrage entgegennimmt:
/// den OAuth-Redirect mit dem Autorisierungscode.
final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private let lock = NSLock()

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        return try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    cont.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let err):
                    listener.stateUpdateHandler = nil
                    cont.resume(throwing: err)
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            codeContinuation = cont
            lock.unlock()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            // Erste Zeile: "GET /?code=…&scope=… HTTP/1.1"
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            var code: String?
            var errorMsg: String?
            if parts.count >= 2,
               let comps = URLComponents(string: "http://127.0.0.1\(parts[1])") {
                code = comps.queryItems?.first(where: { $0.name == "code" })?.value
                errorMsg = comps.queryItems?.first(where: { $0.name == "error" })?.value
            }

            let message = code != nil
                ? "Anmeldung erfolgreich. Sie können dieses Fenster schließen und zur App zurückkehren."
                : "Anmeldung fehlgeschlagen. Bitte in der App erneut versuchen."
            let html = "<html><meta charset='utf-8'><body style='font-family:-apple-system;padding:2em'><h2>\(message)</h2></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                conn.cancel()
            })

            self.lock.lock()
            let cont = self.codeContinuation
            self.codeContinuation = nil
            self.lock.unlock()
            if let code {
                cont?.resume(returning: code)
            } else {
                cont?.resume(throwing: AuthError.flowFailed(errorMsg ?? "Kein Code empfangen."))
            }
        }
    }
}
