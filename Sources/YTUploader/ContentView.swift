import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: QueueStore
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var uploader: UploadManager

    @State private var editingJob: UploadJob?
    @State private var showingEditor = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if !uploader.isOnline {
                Label("Keine Internetverbindung – Uploads werden automatisch fortgesetzt.",
                      systemImage: "wifi.slash")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(.yellow.opacity(0.2))
            }

            if store.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingEditor) {
            JobEditorView(existing: editingJob) { job in
                if store.jobs.contains(where: { $0.id == job.id }) {
                    store.update(job)
                } else {
                    store.jobs.append(job)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Noch keine Upload-Aufträge")
                .font(.title3)
            Text("Lege mit „+“ einen neuen Auftrag an. Die Videos werden dann eines nach dem anderen hochgeladen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobList: some View {
        List {
            ForEach(store.jobs) { job in
                JobRow(job: job)
                    .contextMenu {
                        if job.status != .uploading {
                            Button("Bearbeiten") {
                                editingJob = job
                                showingEditor = true
                            }
                            if job.status == .failed || job.status == .paused {
                                Button("Erneut versuchen") {
                                    var j = job
                                    j.status = .pending
                                    j.errorMessage = nil
                                    store.update(j)
                                }
                            }
                            Button("Entfernen", role: .destructive) {
                                store.remove(job)
                            }
                        }
                    }
            }
            .onMove { from, to in
                store.jobs.move(fromOffsets: from, toOffset: to)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                editingJob = nil
                showingEditor = true
            } label: {
                Label("Neuer Auftrag", systemImage: "plus")
            }
            .help("Neuen Upload-Auftrag anlegen")
            .disabled(!auth.isSignedIn)

            if uploader.isRunning {
                Button {
                    uploader.stop()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .help("Uploads anhalten")
            } else {
                Button {
                    uploader.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .help("Warteschlange abarbeiten")
                .disabled(!auth.isSignedIn || store.nextUploadable == nil)
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            if auth.isSignedIn {
                Label(auth.channelName ?? "Angemeldet", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.green)
            } else {
                Label("Nicht angemeldet", systemImage: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.orange)
            }
            Button {
                showingSettings = true
            } label: {
                Label("Einstellungen", systemImage: "gearshape")
            }
            .help("YouTube-Konto und Zugangsdaten")
        }
    }
}

struct JobRow: View {
    let job: UploadJob

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title.isEmpty ? job.videoFileName : job.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if job.status == .uploading || job.status == .paused, job.totalBytes > 0 {
                    ProgressView(value: job.progress)
                    Text("\(Self.format(bytes: job.bytesSent)) von \(Self.format(bytes: job.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error = job.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            statusBadge
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        var parts = [job.videoFileName]
        if let publishAt = job.publishAt {
            parts.append("Veröffentlichung: \(publishAt.formatted(date: .abbreviated, time: .shortened))")
        } else {
            parts.append(job.privacy.label)
        }
        return parts.joined(separator: " · ")
    }

    private var thumbnail: some View {
        Group {
            if let path = job.thumbnailPath, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 40)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var statusBadge: some View {
        Text(job.status.label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch job.status {
        case .pending: return .secondary
        case .uploading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
