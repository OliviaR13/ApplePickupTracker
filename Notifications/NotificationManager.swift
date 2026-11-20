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
        content.title = "Ready for Pickup"
        content.body = "\(order.productName) is ready at \(order.storeName)."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pickup-ready-\(order.orderNumber)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
