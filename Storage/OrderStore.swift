import Foundation
import Combine

@MainActor
final class OrderStore: ObservableObject {
    @Published private(set) var orders: [PickupOrder] = []
    @Published var lastSync: Date?
    @Published var syncMessage: String?

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("pickup-orders.json")
        load()
    }

    @discardableResult
    func upsert(orderNumber: String, product: String, store: String, status: PickupStatus, messageID: String, date: Date) -> Bool {
        let previousStatus = orders.first(where: { $0.orderNumber == orderNumber })?.status
        if let index = orders.firstIndex(where: { $0.orderNumber == orderNumber }) {
            orders[index].apply(status: status, at: date, sourceMessageID: messageID)
            if orders[index].productName.isEmpty && !product.isEmpty { orders[index].productName = product }
            if orders[index].storeName.isEmpty && !store.isEmpty { orders[index].storeName = store }
        } else {
            orders.append(PickupOrder(orderNumber: orderNumber, productName: product, storeName: store,
                                      status: status, lastUpdated: date, sourceMessageID: messageID,
                                      history: [OrderEvent(status: status, date: date)]))
        }
        orders.sort { $0.lastUpdated > $1.lastUpdated }
        save()
        let currentStatus = orders.first(where: { $0.orderNumber == orderNumber })?.status
        return currentStatus == .readyForPickup && previousStatus != .readyForPickup
    }

    func setSyncResult(_ message: String) {
        lastSync = Date()
        syncMessage = message
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PickupOrder].self, from: data) else { return }
        orders = decoded.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(orders) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
