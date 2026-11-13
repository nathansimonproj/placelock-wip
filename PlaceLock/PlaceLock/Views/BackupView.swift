import SwiftUI

/// Backup status and account deletion. Reached from Rules › Settings.
struct BackupView: View {
    @ObservedObject private var sync = SyncEngine.shared
    @State private var confirmDelete = false
    @State private var deletingAccount = false
    @State private var deleteError: String?

    var body: some View {
        List {
            Section {
                Label(Self.statusText(sync), systemImage: backupSymbol)
                    .foregroundStyle(Self.isProblem(sync) ? Theme.waiting : .secondary)
            } footer: {
                Text(sync.status == .turnedOff
                     ? "Your account was deleted. Turning backup back on starts a new account and backs up this phone's places."
                     : "Places and unlock history are backed up to your account. Blocked apps stay on this phone.")
            }
            .calmRows()

            Section {
                if sync.status == .turnedOff {
                    Button("Turn backup back on", systemImage: "icloud.and.arrow.up") { sync.turnBackOn() }
                } else {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        HStack {
                            Label("Delete account", systemImage: "trash")
                            if deletingAccount { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(deletingAccount)
                    .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete account", role: .destructive) { deleteAccount() }
                    } message: {
                        Text("This permanently deletes your backed-up places and unlock history from the server, and turns backup off. Your places and blocked apps stay on this phone, and blocking keeps working.")
                    }
                }
            }
            .calmRows()
        }
        .calmList()
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't delete your account",
               isPresented: .init(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func deleteAccount() {
        deletingAccount = true
        Task {
            do {
                try await sync.deleteAccount()
            } catch {
                deleteError = "\(SyncEngine.describe(error)). Nothing was deleted. Try again when you're online."
            }
            deletingAccount = false
        }
    }

    /// "Backed up 5 min ago", also shown on the Settings row in Rules.
    static func statusText(_ sync: SyncEngine) -> String {
        let pending = sync.pendingCount > 0 ? " · \(sync.pendingCount) waiting" : ""
        switch sync.status {
        case .off, .turnedOff: return "Off"
        case .idle, .syncing: return "Backing up…" + pending
        case .synced(let date): return "Backed up \(date.formatted(.relative(presentation: .named)))" + pending
        case .failed(let reason): return "Not backed up: \(reason)" + pending
        }
    }

    static func isProblem(_ sync: SyncEngine) -> Bool {
        if case .failed = sync.status { true } else { false }
    }

    private var backupSymbol: String {
        switch sync.status {
        case .failed: "exclamationmark.icloud"
        case .synced: "checkmark.icloud"
        default: "icloud"
        }
    }
}
