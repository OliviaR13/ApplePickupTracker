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
        case .ordered: "已下单"
        case .processing: "正在处理"
        case .shippingToStore: "运送至门店"
        case .readyForPickup: "可以取货"
        case .pickedUp: "已取货"
        case .cancelled: "已取消"
        case .unknown: "状态暂不可用"
        }
    }

    var detail: String {
        switch self {
        case .ordered: "Apple 已收到你的订单。"
        case .processing: "订单正在准备中。"
        case .shippingToStore: "订单正在运送至门店。"
        case .readyForPickup: "订单已备妥，请携带有效身份证件前往门店取货。"
        case .pickedUp: "此订单已取货。"
        case .cancelled: "此订单已取消。"
        case .unknown: "请查看最新的 Apple 邮件了解详情。"
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
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\\n", with: "")

        // Terminal states take precedence over earlier status wording in the same email.
        if value.contains("pickedup") || value.contains("collectedyourorder")
            || value.contains("已取貨") || value.contains("已領取") || value.contains("訂單已取貨") {
            return .pickedUp
        }
        if value.contains("cancelled") || value.contains("canceled")
            || value.contains("已取消") || value.contains("訂單取消") {
            return .cancelled
        }
        if value.contains("readyforpickup") || value.contains("youritemisready") || value.contains("readytopickup")
            || value.contains("已備妥") || value.contains("可供於零售店營業時間內取貨")
            || value.contains("可供取貨") || value.contains("可以取貨") {
            return .readyForPickup
        }
        if value.contains("shippingtostore") || value.contains("onitswaytothestore")
            || value.contains("運送至零售店") || value.contains("正在運送到零售店") {
            return .shippingToStore
        }
        if value.contains("processing") || value.contains("preparingyourorder") || value.contains("beingprepared")
            || value.contains("正在處理") || value.contains("正在準備") {
            return .processing
        }
        if value.contains("orderconfirmation") || value.contains("we'vereceivedyourorder")
            || value.contains("wehavereceivedyourorder") || value.contains("訂單確認")
            || value.contains("已收到你的訂單") || value.contains("已收到訂單") {
            return .ordered
        }
        return .unknown
    }
}
