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

    /// Inserts or updates one order. Pass `persist: false` when applying many messages in a row,
    /// then call `commit()` once so the list is sorted and written to disk a single time.
    @discardableResult
    func upsert(orderNumber: String, product: String, store: String, pickupNote: String? = nil, status: PickupStatus, messageID: String, date: Date, persist: Bool = true) -> Bool {
        let existing = orders.firstIndex(where: { $0.orderNumber == orderNumber })
        let previousStatus = existing.map { orders[$0].status }
        let target: Int
        if let index = existing {
            orders[index].apply(status: status, at: date, sourceMessageID: messageID)
            if orders[index].productName.isEmpty || orders[index].productName == "Apple Store Order", !product.isEmpty {
                orders[index].productName = product
            }
            if shouldAdoptStore(current: orders[index].storeName, new: store) {
                orders[index].storeName = store
            }
            if let pickupNote, !pickupNote.isEmpty { orders[index].pickupNote = pickupNote }
            target = index
        } else {
            orders.append(PickupOrder(orderNumber: orderNumber, productName: product, storeName: store, pickupNote: pickupNote,
                                      status: status, lastUpdated: date, sourceMessageID: messageID,
                                      history: [OrderEvent(status: status, date: date)]))
            target = orders.count - 1
        }
        let becameReady = orders[target].status == .readyForPickup && previousStatus != .readyForPickup
        if persist { commit() }
        return becameReady
    }

    /// Sorts newest-first and saves to disk.
    func commit() {
        orders.sort { $0.lastUpdated > $1.lastUpdated }
        save()
    }

    func setSyncResult(_ message: String) {
        lastSync = Date()
        syncMessage = message
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PickupOrder].self, from: data) else { return }
        orders = decoded.sorted { $0.lastUpdated > $1.lastUpdated }
        sanitizeStoredStoreNames()
    }

    /// Older builds saved Apple's pickup-instruction paragraph as the store name.
    private func sanitizeStoredStoreNames() {
        var changed = false
        for index in orders.indices where AppleMailFields.isInstruction(orders[index].storeName) {
            if orders[index].pickupNote == nil { orders[index].pickupNote = orders[index].storeName }
            orders[index].storeName = ""
            changed = true
        }
        if changed { save() }
    }

    private func shouldAdoptStore(current: String, new: String) -> Bool {
        let incoming = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty, incoming != "零售店", incoming != "Store Pickup", !AppleMailFields.isInstruction(incoming) else { return false }
        let existing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.isEmpty || existing == "零售店" || existing == "Store Pickup" || AppleMailFields.isInstruction(existing) || existing != incoming
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(orders) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
