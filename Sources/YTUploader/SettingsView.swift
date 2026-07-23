import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var ai: AIService

    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Google-API-Zugangsdaten") {
                    TextField("Client-ID", text: $auth.clientID)
                        .textFieldStyle(.roundedBorder)
                    TextField("Client-Secret", text: $auth.clientSecret)
                        .textFieldStyle(.roundedBorder)
                    Text("Einmalig in der Google Cloud Console anlegen – siehe ANLEITUNG.md im Projektordner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("YouTube-Konto") {
                    if auth.isSignedIn {
                        LabeledContent("Angemeldet als", value: auth.channelName ?? "–")
                        Button("Abmelden") { auth.signOut() }
                    } else {
                        Button {
                            signIn()
                        } label: {
                            if busy {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Bei YouTube anmelden …")
                            }
                        }
                        .disabled(busy || auth.clientID.isEmpty || auth.clientSecret.isEmpty)
                        Text("Öffnet den Browser für die Google-Anmeldung.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("KI-Texthilfe (OpenAI)") {
                    SecureField("OpenAI-API-Key", text: $ai.apiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Modell", text: $ai.model)
                        .textFieldStyle(.roundedBorder)
                    Text("API-Key unter platform.openai.com erstellen (unabhängig von ChatGPT Plus, Abrechnung pro Anfrage – Bruchteile eines Cents pro Text). Der Key wird im Schlüsselbund gespeichert. Aktiviert die ✨-Knöpfe im Auftrags-Editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 560)
    }

    private func signIn() {
        busy = true
        errorMessage = nil
        Task {
            do {
                try await auth.signIn()
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }
}
