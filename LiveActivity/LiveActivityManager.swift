import ActivityKit
import Foundation

enum LiveActivityUpdate: Equatable {
    case started
    case updated
    case ended
    case disabled
    case failed(String)
}

@MainActor
final class LiveActivityManager {
    func startOrUpdate(for order: PickupOrder) async -> LiveActivityUpdate {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }
        let state = PickupAttributes.ContentState(status: order.status, lastUpdated: order.lastUpdated, storeName: order.displayStoreName)
        let content = ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .hour, value: 12, to: Date()))
        if let existing = Activity<PickupAttributes>.activities.first(where: { $0.attributes.orderNumber == order.orderNumber }) {
            await existing.update(content)
            if order.status == .pickedUp || order.status == .cancelled {
                await existing.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60 * 60)))
                return .ended
            }
            return .updated
        }
        guard order.status != .pickedUp && order.status != .cancelled else { return .ended }
        let attributes = PickupAttributes(orderNumber: order.orderNumber, productName: order.productName)
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
