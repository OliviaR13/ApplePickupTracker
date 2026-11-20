import MapKit
import UIKit

/// Opens Apple Maps on a pickup store.
@MainActor
enum StoreNavigator {
    static func open(storeName: String) async {
        let query = await searchQuery(for: storeName)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
            item.openInMaps()
            return
        }
        // Fallback: let Maps run the text search itself.
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url { await UIApplication.shared.open(url) }
    }

    /// Prefers the official name and city from Apple's retail list; otherwise "Apple <name>".
    private static func searchQuery(for storeName: String) async -> String {
        if let store = await AppleStoreDirectory.shared.store(matching: storeName) {
            let name = store.name.localizedCaseInsensitiveContains("apple") ? store.name : "Apple \(store.name)"
            return store.city.isEmpty ? name : "\(name) \(store.city)"
        }
        return storeName.localizedCaseInsensitiveContains("apple") ? storeName : "Apple \(storeName)"
    }
}
