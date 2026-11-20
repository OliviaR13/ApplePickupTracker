import BackgroundTasks
import Foundation

@MainActor
final class BackgroundSync {
    static let identifier = "com.example.ApplePickupTracker.refresh"
    static let shared = BackgroundSync()
    private init() {}

    func register(handler: @escaping () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            self.schedule()
            Task {
                await handler()
                refresh.setTaskCompleted(success: true)
            }
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
