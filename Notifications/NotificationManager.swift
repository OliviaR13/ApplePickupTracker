import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
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
