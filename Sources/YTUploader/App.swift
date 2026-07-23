import SwiftUI

@main
struct YTUploaderApp: App {
    @StateObject private var store: QueueStore
    @StateObject private var auth: AuthManager
    @StateObject private var uploader: UploadManager
    @StateObject private var ai = AIService()

    init() {
        let store = QueueStore()
        let auth = AuthManager()
        _store = StateObject(wrappedValue: store)
        _auth = StateObject(wrappedValue: auth)
        _uploader = StateObject(wrappedValue: UploadManager(store: store, auth: auth))

        // Auch als "nackte" Binärdatei (swift run) als reguläre App auftreten.
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("YTUploader") {
            ContentView()
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(uploader)
                .environmentObject(ai)
        }
    }
}
