import SwiftUI
import UniformTypeIdentifiers

/// Formular zum Anlegen bzw. Bearbeiten eines Upload-Auftrags.
struct JobEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: QueueStore
    @EnvironmentObject var ai: AIService

    let existing: UploadJob?
    let onSave: (UploadJob) -> Void

    @State private var videoPath = ""
    @State private var thumbnailPath: String?
    @State private var title = ""
    @State private var videoDescription = ""
    @State private var tagsText = ""
    @State private var categoryId = "22"
    @State private var privacy: Privacy = .publicVideo
    @State private var scheduled = false
    @State private var publishAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var madeForKids = false

    @State private var aiBusy = false
    @State private var aiError: String?
    @State private var previousTitle: String?
    @State private var previousDescription: String?
    @State private var previousTags: String?

    init(existing: UploadJob?, onSave: @escaping (UploadJob) -> Void) {
        self.existing = existing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Dateien") {
                    filePicker(
                        label: "Video",
                        path: videoPath.isEmpty ? nil : videoPath,
                        types: [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
                    ) { videoPath = $0 }

                    filePicker(label: "Thumbnail (optional)", path: thumbnailPath, types: [.jpeg, .png]) {
                        thumbnailPath = $0
                    }
                    if thumbnailPath != nil {
                        Button("Thumbnail entfernen") { thumbnailPath = nil }
                            .buttonStyle(.link)
                    }
                }

                Section("Details") {
                    HStack {
                        TextField("Titel", text: $title)
                            .onChange(of: title) { newValue in
                                if newValue.count > 100 { title = String(newValue.prefix(100)) }
                            }
                        aiMenu(for: .title)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Beschreibung").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            aiMenu(for: .description)
                        }
                        TextEditor(text: $videoDescription)
                            .font(.body)
                            .frame(height: 110)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                    }
                    if let aiError {
                        Text(aiError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        TextField("Tags (durch Komma getrennt)", text: $tagsText)
                        aiMenu(for: .tags)
                    }
                    Picker("Kategorie", selection: $categoryId) {
                        ForEach(Category.all) { cat in
                            Text(cat.label).tag(cat.id)
                        }
                    }
                    Toggle("Speziell für Kinder", isOn: $madeForKids)
                }

                Section("Veröffentlichung") {
                    Toggle("Zeitpunkt planen", isOn: $scheduled)
                    if scheduled {
                        DatePicker("Veröffentlichen am", selection: $publishAt, in: Date()...)
                        SchedulePlanCalendar(selection: $publishAt, planned: plannedEntries)
                        Text("Das Video wird privat hochgeladen und von YouTube zum gewählten Zeitpunkt automatisch öffentlich geschaltet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Sichtbarkeit", selection: $privacy) {
                            ForEach(Privacy.allCases) { p in
                                Text(p.label).tag(p)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? "Zur Warteschlange hinzufügen" : "Speichern") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(videoPath.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 700)
        .onAppear(perform: loadExisting)
    }

    /// Veröffentlichungstermine aller anderen Aufträge (für den Kalender).
    private var plannedEntries: [PlannedEntry] {
        store.jobs
            .filter { $0.id != existing?.id }
            .compactMap { job in
                job.publishAt.map {
                    PlannedEntry(date: $0, title: job.title.isEmpty ? job.videoFileName : job.title)
                }
            }
    }

    // MARK: - KI-Texthilfe

    @ViewBuilder
    private func aiMenu(for field: AIService.Field) -> some View {
        let (hasUndo, disabled): (Bool, Bool) = {
            switch field {
            case .title:
                return (previousTitle != nil,
                        title.trimmingCharacters(in: .whitespaces).isEmpty)
            case .description:
                return (previousDescription != nil,
                        videoDescription.trimmingCharacters(in: .whitespaces).isEmpty)
            case .tags:
                // Tags brauchen keinen bestehenden Text – nur Titel oder Beschreibung als Grundlage
                return (previousTags != nil,
                        title.trimmingCharacters(in: .whitespaces).isEmpty
                            && videoDescription.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }()
        Menu {
            if field == .tags {
                Button("Tags vorschlagen") { runAI(field, .suggest) }
            } else {
                Button("Verbessern") { runAI(field, .improve) }
                Button("Verlängern") { runAI(field, .expand) }
            }
            if hasUndo {
                Divider()
                Button("Rückgängig") { undoAI(field) }
            }
        } label: {
            if aiBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .fixedSize()
        .disabled(aiBusy || !ai.isConfigured || disabled)
        .help(ai.isConfigured
              ? (field == .tags ? "Tags aus Titel und Beschreibung vorschlagen lassen" : "Text mit KI überarbeiten")
              : "Zuerst OpenAI-API-Key in den Einstellungen eintragen")
    }

    private func runAI(_ field: AIService.Field, _ mode: AIService.Mode) {
        aiBusy = true
        aiError = nil
        Task {
            do {
                let result = try await ai.rewrite(
                    field, mode: mode,
                    title: title, description: videoDescription, tags: tagsText
                )
                switch field {
                case .title:
                    previousTitle = title
                    title = result
                case .description:
                    previousDescription = videoDescription
                    videoDescription = result
                case .tags:
                    previousTags = tagsText
                    tagsText = result
                }
            } catch {
                aiError = error.localizedDescription
            }
            aiBusy = false
        }
    }

    private func undoAI(_ field: AIService.Field) {
        switch field {
        case .title:
            if let previousTitle { title = previousTitle }
            previousTitle = nil
        case .description:
            if let previousDescription { videoDescription = previousDescription }
            previousDescription = nil
        case .tags:
            if let previousTags { tagsText = previousTags }
            previousTags = nil
        }
    }

    private func loadExisting() {
        guard let job = existing else { return }
        videoPath = job.videoPath
        thumbnailPath = job.thumbnailPath
        title = job.title
        videoDescription = job.videoDescription
        tagsText = job.tags.joined(separator: ", ")
        categoryId = job.categoryId
        privacy = job.privacy
        madeForKids = job.madeForKids
        if let date = job.publishAt {
            scheduled = true
            publishAt = date
        }
    }

    private func save() {
        var job = existing ?? UploadJob(
            videoPath: "", thumbnailPath: nil, title: "", videoDescription: "",
            tags: [], categoryId: "22", privacy: .publicVideo,
            publishAt: nil, madeForKids: false
        )
        job.videoPath = videoPath
        job.thumbnailPath = thumbnailPath
        job.title = title.trimmingCharacters(in: .whitespaces)
        job.videoDescription = videoDescription
        job.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        job.categoryId = categoryId
        job.privacy = privacy
        job.publishAt = scheduled ? publishAt : nil
        job.madeForKids = madeForKids
        onSave(job)
        dismiss()
    }

    @ViewBuilder
    private func filePicker(label: String, path: String?, types: [UTType], onPick: @escaping (String) -> Void) -> some View {
        LabeledContent(label) {
            HStack {
                if let path {
                    Text((path as NSString).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button(path == nil ? "Auswählen …" : "Ändern …") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = types
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        onPick(url.path)
                    }
                }
            }
        }
    }
}
