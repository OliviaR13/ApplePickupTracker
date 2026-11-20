import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    func startOrUpdate(for order: PickupOrder) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = PickupAttributes.ContentState(status: order.status, lastUpdated: order.lastUpdated, storeName: order.storeName)
        if let existing = Activity<PickupAttributes>.activities.first(where: { $0.attributes.orderNumber == order.orderNumber }) {
            await existing.update(ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .hour, value: 12, to: Date())))
            if order.status == .pickedUp || order.status == .cancelled {
                await existing.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(60 * 60)))
            }
        } else if order.status != .pickedUp && order.status != .cancelled {
            let attributes = PickupAttributes(orderNumber: order.orderNumber, productName: order.productName)
            _ = try? Activity.request(attributes: attributes,
                                      content: ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .hour, value: 12, to: Date())),
                                      pushType: nil)
        }
    }
}
