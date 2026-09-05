import SwiftUI

/// Übernimmt Titel und Beschreibung eines Beitrags von tv.ORF.at:
/// Sendung und Sendedatum wählen, Beiträge laden, einen auswählen.
struct ORFImportView: View {
    @Environment(\.dismiss) private var dismiss

    /// Liefert fertigen Titel und Beschreibungstext zurück.
    let onApply: (String, String) -> Void

    private static let customLabel = "Andere Sendung …"

    @AppStorage("orfLastShow") private var showLabel = ORFShow.all[0].label
    @AppStorage("orfCustomShow") private var customShow = ""
    /// Zuletzt gewähltes Sendedatum merken – beim Anlegen mehrerer Beiträge
    /// derselben Sendung spart das jedes Mal die Datumseingabe.
    @AppStorage("orfLastDate") private var lastDate = 0.0
    @State private var date = Date()

    @State private var busy = false
    @State private var errorMessage: String?
    @State private var broadcasts: [ORFBroadcast] = []
    @State private var selectedBroadcast: ORFBroadcast?
    @State private var items: [ORFItem] = []
    @State private var selectedItem: ORFItem?

    /// Name, der im Videotitel erscheint.
    private var showName: String {
        showLabel == Self.customLabel
            ? customShow.trimmingCharacters(in: .whitespaces)
            : showLabel
    }

    private var searchTerm: String {
        showLabel == Self.customLabel
            ? customShow.trimmingCharacters(in: .whitespaces)
            : (ORFShow.all.first { $0.label == showLabel }?.searchTerm ?? showLabel)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Sendung") {
                    Picker("Sendung", selection: $showLabel) {
                        ForEach(ORFShow.all) { Text($0.label).tag($0.label) }
                        Text(Self.customLabel).tag(Self.customLabel)
                    }
                    if showLabel == Self.customLabel {
                        TextField("Name laut ORF-Programm", text: $customShow)
                            .textFieldStyle(.roundedBorder)
                    }
                    DatePicker("Sendedatum", selection: $date, displayedComponents: .date)

                    HStack {
                        Button {
                            load()
                        } label: {
                            if busy {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Beiträge laden")
                            }
                        }
                        .disabled(busy || showName.isEmpty)
                        Text("Quelle: tv.ORF.at")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                // Mehrere Ausstrahlungen (z. B. Sendung und Spezialausgabe)
                if broadcasts.count > 1 {
                    Section("Gefundene Ausstrahlungen") {
                        ForEach(broadcasts) { b in
                            Button {
                                selectedBroadcast = b
                                loadItems(b)
                            } label: {
                                HStack {
                                    Image(systemName: selectedBroadcast == b
                                          ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(selectedBroadcast == b ? Color.accentColor : .secondary)
                                    Text("\(b.title) — \(b.channel), \(b.startTime) Uhr")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !items.isEmpty {
                    Section("Beiträge") {
                        ForEach(items) { item in
                            beitragRow(item)
                        }
                    }
                }

                if let selectedItem {
                    Section("Titel für YouTube") {
                        Text(ORFService.composedTitle(item: selectedItem.title,
                                                      show: showName, date: date))
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Übernehmen") {
                    if let item = selectedItem {
                        onApply(ORFService.composedTitle(item: item.title, show: showName, date: date),
                                item.text)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedItem == nil)
            }
            .padding()
        }
        .frame(width: 620, height: 660)
        .onAppear { if lastDate > 0 { date = Date(timeIntervalSince1970: lastDate) } }
        .onChange(of: date) { lastDate = $0.timeIntervalSince1970 }
    }

    private func beitragRow(_ item: ORFItem) -> some View {
        Button {
            selectedItem = item
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selectedItem == item ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedItem == item ? Color.accentColor : .secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Beitrag \(item.index): \(item.title)")
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Text(item.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Laden

    private func load() {
        busy = true
        errorMessage = nil
        broadcasts = []
        selectedBroadcast = nil
        items = []
        selectedItem = nil

        Task {
            do {
                let found = try await ORFService.findBroadcasts(show: searchTerm, on: date)
                broadcasts = found
                if let only = found.first, found.count == 1 {
                    selectedBroadcast = only
                    await fetchItems(only)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }

    private func loadItems(_ b: ORFBroadcast) {
        busy = true
        errorMessage = nil
        items = []
        selectedItem = nil
        Task {
            await fetchItems(b)
            busy = false
        }
    }

    private func fetchItems(_ b: ORFBroadcast) async {
        do {
            let loaded = try await ORFService.items(at: b.url)
            items = loaded
            if loaded.count == 1 { selectedItem = loaded[0] }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
