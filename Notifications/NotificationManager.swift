import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyReady(order: PickupOrder) async {
        let content = UNMutableNotificationContent()
        content.title = "Apple 订单可以取货"
        content.body = "\(order.productName) 已在 \(order.displayStoreName) 备妥。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pickup-ready-\(order.orderNumber)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func removePending(orderNumber: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["pickup-ready-\(orderNumber)"]
        )
    }

    func removeAllPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
