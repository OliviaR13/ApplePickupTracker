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
    /// Only activities still on screen. Ended or dismissed ones must not block a fresh request.
    private var running: [Activity<PickupAttributes>] {
        Activity<PickupAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    var runningCount: Int { running.count }

    @discardableResult
    func startOrUpdate(for order: PickupOrder) async -> LiveActivityUpdate {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }
        let state = PickupAttributes.ContentState(status: order.status, lastUpdated: order.lastUpdated, storeName: order.displayStoreName)
        let content = ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .hour, value: 12, to: Date()))
        if let existing = running.first(where: { $0.attributes.orderNumber == order.orderNumber }) {
            await existing.update(content)
            if order.status.isFinished {
                await existing.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60 * 60)))
                return .ended
            }
            return .updated
        }
        guard !order.status.isFinished else { return .ended }
        let attributes = PickupAttributes(orderNumber: order.orderNumber, productName: order.productName)
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Brings every Live Activity in line with the stored orders.
    /// - Running activities are updated; those of finished or removed orders are ended.
    /// - A few of the most recent active orders get a new activity. Starting one for every old
    ///   unfinished order would fill iOS's per-app limit and crowd out the order that matters.
    /// `Activity.request` only works while the app is in the foreground; from a background
    /// refresh only the update/end half takes effect.
    func reconcile(with orders: [PickupOrder], maxNew: Int = 3) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        for activity in running {
            if let order = orders.first(where: { $0.orderNumber == activity.attributes.orderNumber }) {
                await startOrUpdate(for: order)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        let alreadyShown = Set(running.map { $0.attributes.orderNumber })
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        let candidates = orders
            .filter { !$0.status.isFinished && $0.lastUpdated >= cutoff && !alreadyShown.contains($0.orderNumber) }
            .prefix(maxNew)
        for order in candidates {
            await startOrUpdate(for: order)
        }
    }

    func end(orderNumber: String) async {
        for activity in running where activity.attributes.orderNumber == orderNumber {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends every running pickup Live Activity, e.g. after the user clears local data.
    func endAll() async {
        for activity in running {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
