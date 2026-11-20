import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: OrderStore
    @EnvironmentObject private var oauth: GmailOAuth
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var showingSettings = false

    private let syncService: SyncService

    init(syncService: SyncService) { self.syncService = syncService }

    var body: some View {
        NavigationStack {
            Group {
                if store.orders.isEmpty {
                    ContentUnavailableView {
                        Label("No Pickup Orders", systemImage: "bag")
                    } description: {
                        Text(oauth.isConnected ? "Sync Gmail to find Apple Store Pickup orders." : "Connect Gmail to find your Apple Store Pickup orders.")
                    } actions: {
                        Button(oauth.isConnected ? "Sync Gmail" : "Connect Gmail") {
                            Task {
                                if oauth.isConnected { await sync() } else { await connectAndSync() }
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.orders) { order in
                                NavigationLink(value: order) { OrderRow(order: order) }
                            }
                        } header: {
                            HStack {
                                Text("YOUR ORDERS")
                                Spacer()
                                Text("\(store.orders.count)").foregroundStyle(.secondary)
                            }
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Pickup Tracker")
            .navigationDestination(for: PickupOrder.self) { OrderDetailView(order: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await sync() } } label: {
                        if isSyncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }.disabled(isSyncing || !oauth.isConnected)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let lastSync = store.lastSync {
                    Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(onSync: { await sync() }) }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .task { BackgroundSync.shared.schedule() }
    }

    private func connectAndSync() async {
        do { try await oauth.connect(); await sync() }
        catch { errorMessage = error.localizedDescription }
    }

    private func sync() async {
        guard oauth.isConnected else { await connectAndSync(); return }
        isSyncing = true
        defer { isSyncing = false }
        do { try await syncService.sync(); store.setSyncResult("Sync complete") }
        catch { store.setSyncResult("Sync failed"); errorMessage = error.localizedDescription }
    }
}

private struct OrderRow: View {
    let order: PickupOrder
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bag.fill")
                .font(.title2).foregroundStyle(order.status == .readyForPickup ? .green : .primary)
                .frame(width: 48, height: 48).background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(order.productName).font(.headline).lineLimit(1)
                Text(order.storeName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(order.status.title).font(.caption.weight(.semibold)).foregroundStyle(order.status == .readyForPickup ? .green : .secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 4)
    }
}
