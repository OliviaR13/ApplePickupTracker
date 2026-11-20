import Foundation

enum OrderFilter: String, CaseIterable, Identifiable {
    case all, ready, active, finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .ready: "可取货"
        case .active: "进行中"
        case .finished: "已完成"
        }
    }

    func matches(_ order: PickupOrder) -> Bool {
        switch self {
        case .all: true
        case .ready: order.status == .readyForPickup
        case .active: !order.status.isFinished
        case .finished: order.status.isFinished
        }
    }
}
