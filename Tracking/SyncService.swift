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

    func sync() async throws {
        let result = try await outlook.fetchAppleOrderMessages()
        var newlyReady: [PickupOrder] = []
        for message in result.messages {
            let becameReady = store.upsert(orderNumber: message.orderNumber, product: message.productName,
                                           store: message.storeName, pickupNote: message.pickupNote,
                                           recognitionConfidence: message.recognitionConfidence,
                                           status: message.status, messageID: message.messageID, date: message.date)
            if becameReady, let order = store.orders.first(where: { $0.orderNumber == message.orderNumber }) {
                newlyReady.append(order)
            }
        }

        await activity.synchronizeExisting(orders: store.orders)
        for order in newlyReady {
            await NotificationManager.shared.notifyReady(order: order)
        }

        let summary: String
        if result.messages.isEmpty {
            summary = "已连接 Outlook；检查了 \(result.scannedCount) 封邮件，其中 \(result.appleSenderCount) 封来自 Apple，但没有识别到取货订单。"
        } else {
            let highConfidence = result.messages.filter { $0.recognitionConfidence >= 0.8 }.count
            summary = "同步完成：扫描 \(result.scannedCount) 封邮件，识别到 \(result.messages.count) 条订单状态（高可信度 \(highConfidence) 条）。"
        }
        store.setSyncResult(summary)
        BackgroundSync.shared.schedule()
    }
}
