import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: OrderStore
    @EnvironmentObject private var oauth: OutlookOAuth
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var showingAddOrder = false
    @State private var searchText = ""
    @State private var filter: OrderFilter = .all
    @AppStorage("appearance.mode") private var appearanceMode = "system"

    private let syncService: SyncService
    init(syncService: SyncService) { self.syncService = syncService }

    /// Orders after the status filter and the search text are applied.
    private var visibleOrders: [PickupOrder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.orders.filter { order in
            guard filter.matches(order) else { return false }
            guard !query.isEmpty else { return true }
            return order.productName.localizedCaseInsensitiveContains(query)
                || order.displayStoreName.localizedCaseInsensitiveContains(query)
                || order.orderNumber.localizedCaseInsensitiveContains(query)
        }
    }
    private var activeOrders: [PickupOrder] { visibleOrders.filter { !$0.status.isFinished } }
    private var finishedOrders: [PickupOrder] { visibleOrders.filter { $0.status.isFinished } }
    private var readyCount: Int { store.orders.filter { $0.status == .readyForPickup }.count }
    private var syncFailed: Bool { store.syncMessage?.hasPrefix("同步失败") == true }

    var body: some View {
        NavigationStack {
            Group {
                if store.orders.isEmpty {
                    emptyState
                } else {
                    orderList
                }
            }
            .navigationTitle("Apple 取货追踪")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: PickupOrder.self) { OrderDetailView(initial: $0, loadOriginalMail: { messageID in
                try await syncService.fetchOriginalMail(messageID: messageID)
            }) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddOrder = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("手动添加订单")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await sync() } } label: {
                        if isSyncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityLabel("同步")
                    .disabled(isSyncing || !oauth.isConnected)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 10) {
                if let lastSync = store.lastSync, !syncFailed {
                    VStack(spacing: 3) {
                        Text("上次同步")
                            .font(.caption.weight(.semibold))
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 560)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(onSync: { await sync() }) }
            .sheet(isPresented: $showingAddOrder) { AddOrderView() }
            .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .task { BackgroundSync.shared.schedule() }
        .preferredColorScheme(appearanceMode == "dark" ? .dark : appearanceMode == "light" ? .light : nil)
        .animation(.easeInOut(duration: 0.2), value: appearanceMode)
    }

    // MARK: - List

    private var orderList: some View {
        List {
            if isSyncing || store.syncMessage != nil {
                Section { syncStatus }
            }
            Section {
                Picker("筛选", selection: $filter) {
                    ForEach(OrderFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
            if readyCount > 0 && filter == .all && searchText.isEmpty {
                Section { readyBanner }
            }
            if visibleOrders.isEmpty {
                Section { noResults.listRowBackground(Color.clear) }
            }
            if !activeOrders.isEmpty {
                orderSection("进行中", activeOrders)
            }
            if !finishedOrders.isEmpty {
                orderSection("已完成", finishedOrders)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { if oauth.isConnected { await sync() } }
        .searchable(text: $searchText, prompt: "搜索商品、门店或订单号")
    }

    @ViewBuilder
    private var noResults: some View {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("没有符合条件的订单", systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("换一个筛选条件试试。"))
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func orderSection(_ title: String, _ orders: [PickupOrder]) -> some View {
        Section {
            ForEach(orders) { order in
                NavigationLink(value: order) { OrderRow(order: order) }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { remove(order) } label: { Label("移除", systemImage: "trash") }
                    }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(orders.count)").foregroundStyle(.secondary)
            }
        }
    }

    private var readyBanner: some View {
        Label("\(readyCount) 个订单可以取货", systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.vertical, 4)
    }

    // MARK: - Empty state

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

    // MARK: - Sync status

    private var syncStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSyncing {
                ProgressView()
            } else if syncFailed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(isSyncing ? "正在同步 Outlook" : (syncFailed ? "同步失败" : "最近一次同步"))
                    .font(.subheadline.weight(.semibold))
                if let message = store.syncMessage {
                    Text(syncFailed ? String(message.dropFirst("同步失败".count)).trimmingCharacters(in: CharacterSet(charactersIn: "：: ")) : message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if syncFailed && !isSyncing {
                    Button("重试") { Task { await sync() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func remove(_ order: PickupOrder) {
        store.remove(orderNumber: order.orderNumber)
        Task { await LiveActivityManager().end(orderNumber: order.orderNumber) }
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
            let friendly = SyncErrorText.describe(error)
            store.setSyncResult("同步失败：\(friendly)")
            errorMessage = friendly
        }
    }
}

private struct OrderRow: View {
    let order: PickupOrder

    var body: some View {
        HStack(spacing: 14) {
            ProductThumbnailView(imageURL: order.productImageURL, size: 58, cornerRadius: 16)
            VStack(alignment: .leading, spacing: 5) {
                Text(order.productName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(order.displayStoreName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    StatusBadge(status: order.status)
                    Text(order.lastUpdated.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
