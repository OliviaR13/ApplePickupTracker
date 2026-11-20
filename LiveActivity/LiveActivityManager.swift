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
        let state = contentState(for: order)
        let content = ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .hour, value: 12, to: Date()))
        if let existing = activity(for: order.orderNumber) {
            if Self.isTerminal(order.status) {
                await existing.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60 * 60)))
                return .ended
            }
            await existing.update(content)
            return .updated
        }
        guard !isTerminal(order.status) else { return .ended }
        let attributes = PickupAttributes(orderNumber: order.orderNumber, productName: order.productName)
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Updates only activities explicitly started by the user; never creates activities during mailbox sync.
    func synchronizeExisting(orders: [PickupOrder]) async {
        let byNumber = Dictionary(uniqueKeysWithValues: orders.map { ($0.orderNumber, $0) })
        for activity in Activity<PickupAttributes>.activities {
            guard let order = byNumber[activity.attributes.orderNumber] else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let content = ActivityContent(state: contentState(for: order),
                                          staleDate: Calendar.current.date(byAdding: .hour, value: 12, to: Date()))
            if Self.isTerminal(order.status) {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60 * 60)))
            } else {
                await activity.update(content)
            }
        }
    }

    func end(orderNumber: String) async {
        guard let activity = activity(for: orderNumber) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    func endAll() async {
        for activity in Activity<PickupAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func isActive(orderNumber: String) -> Bool {
        activity(for: orderNumber) != nil
    }

    private func activity(for orderNumber: String) -> Activity<PickupAttributes>? {
        Activity<PickupAttributes>.activities.first { $0.attributes.orderNumber == orderNumber }
    }

    private func contentState(for order: PickupOrder) -> PickupAttributes.ContentState {
        PickupAttributes.ContentState(status: order.status, lastUpdated: order.lastUpdated,
                                      storeName: order.displayStoreName)
    }

    private static func isTerminal(_ status: PickupStatus) -> Bool {
        status == .pickedUp || status == .cancelled
    }

}
