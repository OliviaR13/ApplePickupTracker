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
    private static let parserVersion = 2
    private static let lastScanKey = "outlook.lastScanDate"
    private static let parserVersionKey = "outlook.parserVersion"

    /// Forgets the incremental-scan state so the next sync re-reads the whole window.
    static func resetScanState() {
        UserDefaults.standard.removeObject(forKey: lastScanKey)
        UserDefaults.standard.removeObject(forKey: parserVersionKey)
    }

    /// Foreground, background-refresh and manual syncs can overlap; only one may run at a time.
    private var isRunning = false

    /// Incremental sync: only look at mail since the last successful scan (3-day overlap).
    /// Falls back to a full scan on first run, when no orders are stored, or after a parser update.
    private func scanStart() -> Date? {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.parserVersionKey) == Self.parserVersion,
              !store.orders.isEmpty,
              let last = defaults.object(forKey: Self.lastScanKey) as? Date else { return nil }
        return Calendar.current.date(byAdding: .day, value: -3, to: last)
    }

    func sync() async throws {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let scanStartedAt = Date()
        let result = try await outlook.fetchAppleOrderMessages(since: scanStart())
        var newlyReadyOrderNumbers = Set<String>()
        for message in result.messages {
            let becameReady = store.upsert(orderNumber: message.orderNumber, product: message.productName, store: message.storeName,
                                           pickupNote: message.pickupNote, status: message.status, messageID: message.messageID, date: message.date,
                                           persist: false)
            if becameReady { newlyReadyOrderNumbers.insert(message.orderNumber) }
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
            summary = "同步完成：扫描 \(result.scannedCount) 封邮件，识别到 \(result.messages.count) 条订单状态。"
        }
        store.setSyncResult(summary)
        UserDefaults.standard.set(scanStartedAt, forKey: Self.lastScanKey)
        UserDefaults.standard.set(Self.parserVersion, forKey: Self.parserVersionKey)
        BackgroundSync.shared.schedule()
    }
}
