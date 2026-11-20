import SwiftUI
import BackgroundTasks

@main
struct ApplePickupTrackerApp: App {
    @StateObject private var store = OrderStore()
    @StateObject private var oauth = OutlookOAuth()
    @Environment(\.scenePhase) private var scenePhase

    private var syncService: SyncService { SyncService(outlook: OutlookClient(oauth: oauth), store: store) }

    var body: some Scene {
        WindowGroup {
            ContentView(syncService: syncService)
                .environmentObject(store)
                .environmentObject(oauth)
                .task {
                    await NotificationManager.shared.requestPermission()
                    BackgroundSync.shared.register {
                        do { try await self.syncService.sync() }
                        catch { self.store.setSyncResult("后台同步失败：\\(error.localizedDescription)") }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, oauth.isConnected {
                        Task { try? await syncService.sync() }
                    }
                }
        }
    }
}
