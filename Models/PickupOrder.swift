import Foundation

struct PickupOrder: Codable, Identifiable, Hashable {
    var id: String { orderNumber }
    let orderNumber: String
    var productName: String
    var storeName: String
    var status: PickupStatus
    var lastUpdated: Date
    var sourceMessageID: String
    var history: [OrderEvent]

    mutating func apply(status newStatus: PickupStatus, at date: Date, sourceMessageID: String) {
        guard date >= lastUpdated else { return }
        if newStatus < status && newStatus != .cancelled { return }
        guard newStatus != status else {
            if date > lastUpdated { lastUpdated = date }
            return
        }
        status = newStatus
        lastUpdated = date
        self.sourceMessageID = sourceMessageID
        history.append(OrderEvent(status: newStatus, date: date))
    }
}

struct OrderEvent: Codable, Hashable, Identifiable {
    var id: String { "\(status.rawValue)-\(date.timeIntervalSince1970)" }
    let status: PickupStatus
    let date: Date
}

enum PickupStatus: String, Codable, CaseIterable, Comparable {
    case ordered, processing, shippingToStore, readyForPickup, pickedUp, cancelled, unknown

    var title: String {
        switch self {
        case .ordered: "Order Placed"
        case .processing: "Processing"
        case .shippingToStore: "Shipping to Store"
        case .readyForPickup: "Ready for Pickup"
        case .pickedUp: "Picked Up"
        case .cancelled: "Cancelled"
        case .unknown: "Status unavailable"
        }
    }

    var detail: String {
        switch self {
        case .ordered: "Apple received your order."
        case .processing: "Your order is being prepared."
        case .shippingToStore: "Your order is on its way to the store."
        case .readyForPickup: "Your order is ready. Bring a valid ID when collecting it."
        case .pickedUp: "This order has been collected."
        case .cancelled: "This order was cancelled."
        case .unknown: "Open the latest Apple email for details."
        }
    }

    var progress: Double {
        switch self {
        case .ordered: 0.15
        case .processing: 0.35
        case .shippingToStore: 0.65
        case .readyForPickup: 0.88
        case .pickedUp: 1
        case .cancelled, .unknown: 0
        }
    }

    static func < (lhs: PickupStatus, rhs: PickupStatus) -> Bool {
        lhs.progress < rhs.progress
    }

    static func detect(in text: String) -> PickupStatus {
        let value = text.lowercased()
        if value.contains("ready for pickup") || value.contains("your item is ready") || value.contains("ready to pick up") { return .readyForPickup }
        if value.contains("picked up") || value.contains("collected your order") { return .pickedUp }
        if value.contains("cancelled") || value.contains("canceled") { return .cancelled }
        if value.contains("shipping to store") || value.contains("on its way to the store") { return .shippingToStore }
        if value.contains("processing") || value.contains("preparing your order") || value.contains("being prepared") { return .processing }
        if value.contains("order confirmation") || value.contains("we've received your order") || value.contains("we have received your order") { return .ordered }
        return .unknown
    }
}
