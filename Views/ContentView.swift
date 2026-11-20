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
                    emptyState
                } else {
                    List {
                        if isSyncing || store.syncMessage != nil {
                            Section {
                                syncStatus
                            }
                        }
                        Section {
                            ForEach(store.orders) { order in
                                NavigationLink(value: order) { OrderRow(order: order) }
                                    .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18))
                            }
                        } header: {
                            HStack {
                                Text("YOUR ORDERS")
                                Spacer()
                                Text("\(store.orders.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Pickup Tracker")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: PickupOrder.self) { OrderDetailView(order: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape").font(.body.weight(.semibold)) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await sync() } } label: {
                        if isSyncing { ProgressView() } else { Label("Sync", systemImage: "arrow.clockwise") }
                    }
                    .disabled(isSyncing || !oauth.isConnected)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let lastSync = store.lastSync {
                    VStack(spacing: 3) {
                        Text(store.syncMessage ?? "Last synced")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Pickup Orders", systemImage: "bag")
                .font(.title2)
        } description: {
            Text(emptyDescription)
                .font(.body)
                .multilineTextAlignment(.center)
        } actions: {
            VStack(spacing: 14) {
                if isSyncing {
                    ProgressView("正在检查 Gmail 邮件…")
                        .padding(.vertical, 8)
                } else {
                    Button(oauth.isConnected ? "Sync Gmail" : "Connect Gmail") {
                        Task {
                            if oauth.isConnected { await sync() } else { await connectAndSync() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                if let message = store.syncMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 300)
                }
            }
        }
    }

    private var emptyDescription: String {
        if isSyncing { return "正在读取 Apple Store 订单邮件。" }
        return oauth.isConnected
            ? "Gmail 已连接。点击下方按钮，扫描 Apple Store 取货订单。"
            : "连接 Gmail 后，自动查找 Apple Store Pickup 订单。"
    }

    private var syncStatus: some View {
        HStack(spacing: 12) {
            if isSyncing { ProgressView() }
            else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            VStack(alignment: .leading, spacing: 4) {
                Text(isSyncing ? "正在同步 Gmail" : "最近一次同步")
                    .font(.subheadline.weight(.semibold))
                if let message = store.syncMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func connectAndSync() async {
        do { try await oauth.connect(); await sync() }
        catch { errorMessage = error.localizedDescription }
    }

    private func sync() async {
        guard oauth.isConnected else { await connectAndSync(); return }
        isSyncing = true
        defer { isSyncing = false }
        do { try await syncService.sync() }
        catch {
            store.setSyncResult("同步失败：\(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

private struct OrderRow: View {
    let order: PickupOrder
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bag.fill")
                .font(.title2)
                .foregroundStyle(order.status == .readyForPickup ? .green : .primary)
                .frame(width: 54, height: 54)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 6) {
                Text(order.productName).font(.headline).lineLimit(2)
                Text(order.storeName).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text(order.status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(order.status == .readyForPickup ? .green : .secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
