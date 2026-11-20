import Foundation

@MainActor
final class SyncService {
    private let gmail: GmailClient
    private let store: OrderStore
    private let activity = LiveActivityManager()

    init(gmail: GmailClient, store: OrderStore) { self.gmail = gmail; self.store = store }

    func sync() async throws {
        let messages = try await gmail.fetchAppleOrderMessages()
        var newlyReady: [PickupOrder] = []
        for message in messages {
            let becameReady = store.upsert(orderNumber: message.orderNumber, product: message.productName, store: message.storeName,
                                           status: message.status, messageID: message.messageID, date: message.date)
            if becameReady, let order = store.orders.first(where: { $0.orderNumber == message.orderNumber }) {
                newlyReady.append(order)
            }
        }
        for order in store.orders where order.status != .pickedUp && order.status != .cancelled {
            await activity.startOrUpdate(for: order)
        }
        for order in newlyReady {
            await NotificationManager.shared.notifyReady(order: order)
        }
        store.setSyncResult("Found \(messages.count) Apple order emails")
        BackgroundSync.shared.schedule()
    }
}
