import SwiftUI
import BackgroundTasks

@main
struct ApplePickupTrackerApp: App {
    @StateObject private var store = OrderStore()
    @StateObject private var oauth = GmailOAuth()
    @Environment(\.scenePhase) private var scenePhase

    private var syncService: SyncService { SyncService(gmail: GmailClient(oauth: oauth), store: store) }

    var body: some Scene {
        WindowGroup {
            ContentView(syncService: syncService)
                .environmentObject(store)
                .environmentObject(oauth)
                .task {
                    await NotificationManager.shared.requestPermission()
                    BackgroundSync.shared.register {
                        do { try await self.syncService.sync() }
                        catch { self.store.setSyncResult("Background sync failed") }
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
