import Foundation

@MainActor
final class SyncService {
    private let outlook: OutlookClient
    private let store: OrderStore
    private let activity = LiveActivityManager()

    init(outlook: OutlookClient, store: OrderStore) {
        self.outlook = outlook
        self.store = store
    }

    /// Bump when the mail parser changes so the next sync re-scans the full window.
    private static let parserVersion = 8
    private static let lastScanKey = "outlook.lastScanDate"
    private static let parserVersionKey = "outlook.parserVersion"

    /// Forgets the incremental-scan state so the next sync re-reads the whole window.
    static func resetScanState() {
        UserDefaults.standard.removeObject(forKey: lastScanKey)
        UserDefaults.standard.removeObject(forKey: parserVersionKey)
    }

    /// Foreground, background-refresh and manual callers share one in-flight sync.
    private var syncTask: Task<Void, Error>?

    /// Incremental sync: only look at mail since the last successful scan (3-day overlap).
    /// Falls back to a full scan on first run, when no orders are stored, or after a parser update.
    private func scanStart() -> Date? {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.parserVersionKey) == Self.parserVersion,
              !store.orders.isEmpty,
              let last = defaults.object(forKey: Self.lastScanKey) as? Date else { return nil }
        let overlap = Calendar.current.date(byAdding: .day, value: -3, to: last)
        let pendingReadyDates = store.orders
            .filter { $0.status == .readyForPickup }
            .compactMap(\.readyForPickupAt)
        guard let earliestPending = pendingReadyDates.min() else { return overlap }
        return min(overlap ?? earliestPending, earliestPending)
    }

    func fetchOriginalMail(messageID: String) async throws -> OriginalMailMessage {
        try await outlook.fetchOriginalMail(messageID: messageID)
    }

    func sync() async throws {
        if let syncTask {
            try await syncTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.syncTask = nil }
            try await self.performSync()
        }
        syncTask = task
        try await task.value
    }

    private func performSync() async throws {
        let scanStartedAt = Date()
        let result = try await outlook.fetchAppleOrderMessages(since: scanStart())
        var newlyReadyOrderNumbers = Set<String>()
        for message in result.messages {
            let becameReady = store.upsert(orderNumber: message.orderNumber, product: message.productName, store: message.storeName,
                                           pickupNote: message.pickupNote, metadata: message.metadata,
                                           productImageURL: message.productImageURL, pickupQRCode: message.pickupQRCode, walletPassURL: message.walletPassURL, alerts: message.alerts, status: message.status, messageID: message.messageID, date: message.date,
                                           persist: false)
            if becameReady { newlyReadyOrderNumbers.insert(message.orderNumber) }
        }
        for message in result.messages {
            guard let order = store.order(withNumber: message.orderNumber) else { continue }
            for alert in message.alerts { await NotificationManager.shared.notifyAlert(alert, order: order) }
        }
        let previouslyCompleted = Set(store.orders.filter { $0.status == .completed }.map(\.orderNumber))
        let autoCompletedCount = store.completeExpiredPickupOrders()
        if autoCompletedCount > 0 {
            for order in store.orders where order.status == .completed && !previouslyCompleted.contains(order.orderNumber) {
                await NotificationManager.shared.notifyCompleted(order: order)
            }
        }
        if !result.messages.isEmpty { store.commit() }
        await activity.reconcile(with: store.orders)

        // Notify only if the final state after applying every fetched email is still ready.
        // This avoids a stale "ready for pickup" alert when a later email already says picked up.
        let newlyReady = store.orders.filter {
            newlyReadyOrderNumbers.contains($0.orderNumber) && $0.status == .readyForPickup
        }
        for order in newlyReady {
            await NotificationManager.shared.notifyReady(order: order)
        }

        let summary: String
        if result.messages.isEmpty {
            summary = "已连接 Outlook；检查了 \(result.scannedCount) 封邮件，其中 \(result.appleSenderCount) 封来自 Apple，但没有识别到取货订单。"
        } else {
            summary = "同步完成：扫描 \(result.scannedCount) 封邮件，识别到 \(result.messages.count) 条订单状态。" + (autoCompletedCount > 0 ? " 自动完结 \(autoCompletedCount) 笔订单。" : "")
        }
        store.setSyncResult(summary)
        UserDefaults.standard.set(scanStartedAt, forKey: Self.lastScanKey)
        UserDefaults.standard.set(Self.parserVersion, forKey: Self.parserVersionKey)
        BackgroundSync.shared.schedule()
    }
}
