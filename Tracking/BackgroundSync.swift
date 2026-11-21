import BackgroundTasks
import Foundation

@MainActor
final class BackgroundSync {
    static let identifier = "com.example.ApplePickupTracker.refresh"
    static let shared = BackgroundSync()
    private init() {}

    func register(handler: @escaping () async throws -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.schedule()

            let work = Task {
                do {
                    try await handler()
                    refresh.setTaskCompleted(success: true)
                } catch {
                    refresh.setTaskCompleted(success: false)
                }
            }
            refresh.expirationHandler = {
                work.cancel()
            }
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
