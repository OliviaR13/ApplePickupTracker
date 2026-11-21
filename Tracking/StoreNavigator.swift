import MapKit
import UIKit

/// Opens the exact pickup destination supplied by Apple's email whenever available.
@MainActor
enum StoreNavigator {
    static func open(storeName: String, navigationURL: String? = nil) async {
        if let navigationURL, let url = validatedNavigationURL(navigationURL) {
            await UIApplication.shared.open(url)
            return
        }

        let query = await searchQuery(for: storeName)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
            item.openInMaps()
            return
        }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url { await UIApplication.shared.open(url) }
    }

    /// Only open known Apple Maps or Apple retail URLs extracted from Apple's email.
    private static func validatedNavigationURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              let host = url.host?.lowercased(),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        if host == "maps.apple.com" {
            let hasDestination = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains {
                $0.name.lowercased() == "daddr" && !($0.value ?? "").isEmpty
            } ?? false
            return hasDestination ? url : nil
        }
        if host == "apple.com" || host == "www.apple.com" {
            return url.path.lowercased().contains("/retail/") ? url : nil
        }
        return nil
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
