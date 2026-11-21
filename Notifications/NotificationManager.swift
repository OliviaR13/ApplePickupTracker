import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyAlert(_ alert: OrderAlert, order: PickupOrder) async {
        let key = alert.id.hasPrefix("delay-") ? "notifications.delayed" : "notifications.exceptions"
        let enabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        let sentKey = "notifications.sent.\(alert.id)"
        guard enabled, !UserDefaults.standard.bool(forKey: sentKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = "\(order.productName)：\(alert.detail)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "order-alert-\(alert.id)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            UserDefaults.standard.set(true, forKey: sentKey)
        } catch {
            // Leave the alert unsent so the next successful sync can retry it.
        }
    }

    func notifyCompleted(order: PickupOrder) async {
        let enabled = UserDefaults.standard.object(forKey: "notifications.completed") as? Bool ?? true
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "订单已自动完结"
        content.body = "\(order.productName) 已超过设置的取货等待期限。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "order-completed-\(order.orderNumber)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func notifyReady(order: PickupOrder) async {
        let enabled = UserDefaults.standard.object(forKey: "notifications.ready") as? Bool ?? true
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "可以取货了"
        content.body = "\(order.productName) 已在 \(order.displayStoreName) 备妥，请携带有效身份证件前往。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pickup-ready-\(order.orderNumber)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
