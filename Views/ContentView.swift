import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: OrderStore
    @EnvironmentObject private var oauth: OutlookOAuth
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
                            Section { syncStatus }
                        }
                        Section {
                            ForEach(store.orders) { order in
                                NavigationLink(value: order) { OrderRow(order: order) }
                                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            }
                        } header: {
                            HStack {
                                Text("取货订单")
                                Spacer()
                                Text("\(store.orders.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Apple 取货追踪")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: PickupOrder.self) { OrderDetailView(order: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .toolbarGlassButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await sync() } } label: {
                        if isSyncing { ProgressView() } else { Label("同步", systemImage: "arrow.clockwise") }
                    }
                    .toolbarGlassButton()
                    .disabled(isSyncing || !oauth.isConnected)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 10) {
                if let lastSync = store.lastSync {
                    VStack(spacing: 3) {
                        Text(store.syncMessage ?? "上次同步")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 560)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(onSync: { await sync() }) }
            .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .task { BackgroundSync.shared.schedule() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有取货订单", systemImage: "bag")
                .font(.title2)
        } description: {
            Text(emptyDescription).font(.body).multilineTextAlignment(.center)
        } actions: {
            VStack(spacing: 14) {
                if isSyncing {
                    ProgressView("正在检查 Outlook 邮件…").padding(.vertical, 8)
                } else {
                    Button(oauth.isConnected ? "同步 Outlook 邮件" : "连接 Outlook") {
                        Task {
                            if oauth.isConnected { await sync() } else { await connectAndSync() }
                        }
                    }
                    .controlSize(.large)
                    .liquidGlassProminentButton()
                }
                if let message = store.syncMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: 300)
                }
            }
        }
    }

    private var emptyDescription: String {
        if isSyncing { return "正在查找 Apple Store 订单和取货通知。" }
        return oauth.isConnected
            ? "Outlook 已连接。同步邮箱以查找 Apple Store 取货订单。"
            : "连接个人 Outlook 邮箱，自动查找 Apple Store Pickup 订单。"
    }

    private var syncStatus: some View {
        HStack(spacing: 12) {
            if isSyncing { ProgressView() }
            else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            VStack(alignment: .leading, spacing: 4) {
                Text(isSyncing ? "正在同步 Outlook" : "最近一次同步").font(.subheadline.weight(.semibold))
                if let message = store.syncMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(.vertical, 6)
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
        HStack(spacing: 14) {
            Image(systemName: "bag.fill")
                .font(.title2).foregroundStyle(order.status == .readyForPickup ? .green : .primary)
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(order.productName).font(.headline).lineLimit(2)
                Text(order.storeName).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text(order.status.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(order.status == .readyForPickup ? .green : .secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 4).contentShape(Rectangle())
    }
}
