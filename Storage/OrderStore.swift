import Foundation
import Combine

@MainActor
final class OrderStore: ObservableObject {
    @Published private(set) var orders: [PickupOrder] = []
    @Published var lastSync: Date?
    @Published var syncMessage: String?

    private let fileURL: URL
    private static let ignoredKey = "orders.ignoredNumbers"
    /// Orders the user removed by hand. Later syncs must not bring them back.
    private var ignoredNumbers = Set(UserDefaults.standard.stringArray(forKey: OrderStore.ignoredKey) ?? [])

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("pickup-orders.json")
        load()
    }

    /// Inserts or updates one order. Pass `persist: false` when applying many messages in a row,
    /// then call `commit()` once so the list is sorted and written to disk a single time.
    @discardableResult
    func upsert(orderNumber: String, product: String, store: String, pickupNote: String? = nil,
                metadata: AppleOrderMetadata? = nil, productImageURL: String? = nil, pickupQRCode: String? = nil, walletPassURL: String? = nil, alerts: [OrderAlert] = [], status: PickupStatus, messageID: String, date: Date,
                persist: Bool = true) -> Bool {
        guard !ignoredNumbers.contains(orderNumber) else { return false }
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
            if let metadata {
                if let value = metadata.quantity { orders[index].quantity = value }
                if let value = metadata.productAmount { orders[index].productAmount = value }
                if let value = metadata.subtotal { orders[index].subtotal = value }
                if let value = metadata.shippingFee { orders[index].shippingFee = value }
                if let value = metadata.totalAmount { orders[index].totalAmount = value }
                if let value = metadata.currencyCode { orders[index].currencyCode = value }
                if let value = metadata.storeAddress, !value.isEmpty { orders[index].storeAddress = value }
                if let value = metadata.storePostalCode { orders[index].storePostalCode = value }
                if let value = metadata.storePhone { orders[index].storePhone = value }
            }
            if status == .readyForPickup, orders[index].readyForPickupAt == nil {
                orders[index].readyForPickupAt = date
            }
            if let productImageURL, !productImageURL.isEmpty { orders[index].productImageURL = productImageURL }
            if let pickupQRCode, !pickupQRCode.isEmpty { orders[index].pickupQRCode = pickupQRCode }
            if let walletPassURL, !walletPassURL.isEmpty { orders[index].walletPassURL = walletPassURL }
            if !alerts.isEmpty {
                var saved = orders[index].alerts ?? []
                for alert in alerts where !saved.contains(where: { $0.id == alert.id && abs($0.date.timeIntervalSince(alert.date)) < 60 }) {
                    saved.append(alert)
                }
                orders[index].alerts = saved.sorted { $0.date > $1.date }
            }
            target = index
        } else {
            orders.append(PickupOrder(orderNumber: orderNumber, productName: product, productImageURL: productImageURL,
                                      storeName: store, pickupNote: pickupNote,
                                      quantity: metadata?.quantity, productAmount: metadata?.productAmount,
                                      subtotal: metadata?.subtotal, shippingFee: metadata?.shippingFee,
                                      totalAmount: metadata?.totalAmount, currencyCode: metadata?.currencyCode,
                                      storeAddress: metadata?.storeAddress, storePostalCode: metadata?.storePostalCode,
                                      storePhone: metadata?.storePhone,
                                      pickupQRCode: pickupQRCode, walletPassURL: walletPassURL,
                                      status: status, lastUpdated: date, sourceMessageID: messageID,
                                      history: [OrderEvent(status: status, date: date, messageID: messageID)], alerts: alerts.isEmpty ? nil : alerts))
            target = orders.count - 1
        }
        let becameReady = orders[target].status == .readyForPickup && previousStatus != .readyForPickup
        if persist { commit() }
        return becameReady
    }

    /// Automatically closes pickup orders seven days after the ready email,
    /// unless any delay notice has been detected for that order.
    @discardableResult
    func completeExpiredPickupOrders(now: Date = Date()) -> Int {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "orders.autoCompleteEnabled") as? Bool ?? true
        guard enabled else { return 0 }
        let days = defaults.object(forKey: "orders.autoCompleteDays") as? Int ?? 7
        let interval = TimeInterval(days) * 24 * 60 * 60
        var completedCount = 0
        for index in orders.indices {
            guard orders[index].status == .readyForPickup,
                  let readyAt = orders[index].readyForPickupAt,
                  now.timeIntervalSince(readyAt) >= interval else { continue }
            let hasDelayNotice = (orders[index].alerts ?? []).contains {
                $0.id.hasPrefix("delay-") || $0.title.localizedCaseInsensitiveContains("延期")
            }
            guard !hasDelayNotice else { continue }

            let completionDate = readyAt.addingTimeInterval(interval)
            orders[index].status = .completed
            orders[index].lastUpdated = completionDate
            orders[index].history.append(OrderEvent(status: .completed, date: completionDate))
            completedCount += 1
        }
        if completedCount > 0 { commit() }
        return completedCount
    }

    /// Records a user-confirmed pickup when Apple doesn't send a separate pickup email.
    func markPickedUp(orderNumber: String, at date: Date = Date()) {
        guard let index = orders.firstIndex(where: { $0.orderNumber == orderNumber }),
              orders[index].status == .readyForPickup else { return }
        orders[index].status = .pickedUp
        orders[index].lastUpdated = date
        orders[index].history.append(OrderEvent(status: .pickedUp, date: date, messageID: "manual"))
        commit()
    }

    /// Sorts newest-first and saves to disk.
    func commit() {
        orders.sort { $0.lastUpdated > $1.lastUpdated }
        save()
    }

    /// Removes an order for good: it is also remembered so a later sync does not re-add it.
    func remove(orderNumber: String) {
        orders.removeAll { $0.orderNumber == orderNumber }
        ignoredNumbers.insert(orderNumber)
        persistIgnored()
        save()
    }

    /// Adds an order the user typed in. Later Apple emails with the same number update it as usual.
    func addManual(orderNumber: String, product: String, store: String, status: PickupStatus) {
        ignoredNumbers.remove(orderNumber)
        persistIgnored()
        upsert(orderNumber: orderNumber, product: product, store: store, status: status, messageID: "manual", date: Date())
    }

    private func persistIgnored() {
        UserDefaults.standard.set(Array(ignoredNumbers), forKey: Self.ignoredKey)
    }

    func order(withNumber number: String) -> PickupOrder? {
        orders.first { $0.orderNumber == number }
    }

    /// Removes every saved order and the incremental-scan bookkeeping so the next sync starts fresh.
    func clearAll() {
        orders = []
        lastSync = nil
        syncMessage = nil
        ignoredNumbers = []
        UserDefaults.standard.removeObject(forKey: Self.ignoredKey)
        try? FileManager.default.removeItem(at: fileURL)
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
