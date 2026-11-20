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
    func upsert(orderNumber: String, product: String, store: String, pickupNote: String? = nil,
                recognitionConfidence: Double? = nil, status: PickupStatus, messageID: String, date: Date) -> Bool {
        let previousStatus = orders.first(where: { $0.orderNumber == orderNumber })?.status
        if let index = orders.firstIndex(where: { $0.orderNumber == orderNumber }) {
            orders[index].apply(status: status, at: date, sourceMessageID: messageID)
            if (orders[index].productName.isEmpty || orders[index].productName == "Apple Store Order"), !product.isEmpty {
                orders[index].productName = product
            }
            if shouldAdoptStore(current: orders[index].storeName, new: store) {
                orders[index].storeName = store
            }
            if let pickupNote, !pickupNote.isEmpty { orders[index].pickupNote = pickupNote }
            if let recognitionConfidence,
               recognitionConfidence > (orders[index].recognitionConfidence ?? 0) {
                orders[index].recognitionConfidence = recognitionConfidence
            }
        } else {
            orders.append(PickupOrder(orderNumber: orderNumber, productName: product, storeName: store,
                                      pickupNote: pickupNote, recognitionConfidence: recognitionConfidence,
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

    func deleteOrder(orderNumber: String) {
        orders.removeAll { $0.orderNumber == orderNumber }
        save()
    }

    func deleteAllOrders() {
        orders.removeAll()
        lastSync = nil
        syncMessage = nil
        save()
    }

    /// Creates a user-selected export file; order data remains local unless the user shares it.
    func makeExportFile() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(orders)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplePickupTracker-Orders-\\(formatter.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
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
