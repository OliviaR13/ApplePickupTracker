import SwiftUI

/// Owns the app-wide objects once, so `SyncService` is not rebuilt on every `body` evaluation.
@MainActor
final class AppContainer: ObservableObject {
    let store: OrderStore
    let oauth: OutlookOAuth
    let syncService: SyncService

    init() {
        let store = OrderStore()
        let oauth = OutlookOAuth()
        self.store = store
        self.oauth = oauth
        self.syncService = SyncService(outlook: OutlookClient(oauth: oauth), store: store)
    }
}
