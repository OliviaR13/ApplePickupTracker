import SwiftUI
import BackgroundTasks

@main
struct ApplePickupTrackerApp: App {
    @StateObject private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(syncService: container.syncService)
                .environmentObject(container.store)
                .environmentObject(container.oauth)
                .task {
                    await NotificationManager.shared.requestPermission()
                    let container = container
                    BackgroundSync.shared.register {
                        do {
                            try await container.syncService.sync()
                        } catch {
                            container.store.setSyncResult("同步失败：\(SyncErrorText.describe(error))")
                            throw error
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, container.oauth.isConnected {
                        Task {
                            do {
                                try await container.syncService.sync()
                            } catch {
                                container.store.setSyncResult("同步失败：\(SyncErrorText.describe(error))")
                            }
                        }
                    }
                }
        }
    }
}
