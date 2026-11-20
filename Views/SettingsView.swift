import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var oauth: GmailOAuth
    @EnvironmentObject private var store: OrderStore
    @Environment(\.dismiss) private var dismiss
    let onSync: () async -> Void
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gmail") {
                    if oauth.isConnected {
                        Label("Gmail connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Sync now") { Task { isWorking = true; await onSync(); isWorking = false } }.disabled(isWorking)
                        Button("Disconnect Gmail", role: .destructive) { oauth.disconnect() }
                    } else {
                        Text("Connect Gmail with read-only access to find Apple order emails.").foregroundStyle(.secondary)
                        Button("Connect Gmail") {
                            Task {
                                isWorking = true
                                do { try await oauth.connect(); await onSync() }
                                catch { message = error.localizedDescription }
                                isWorking = false
                            }
                        }.disabled(isWorking)
                    }
                }
                Section("Privacy") {
                    Label("Email content is processed on this iPhone", systemImage: "iphone")
                    Label("Order data stays in local storage", systemImage: "lock.fill")
                    Label("Gmail permission: read-only", systemImage: "envelope.badge")
                }
                Section("Sync") {
                    LabeledContent("Last sync", value: store.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    Text("iOS schedules background refresh when system resources allow. Refresh timing is not guaranteed.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Gmail", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }
}
