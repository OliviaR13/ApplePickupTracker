import Foundation

struct AppleStore: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var city: String
    var imageURL: URL

    /// Hero photo used by apple.com retail pickup (`storeImageUrl` on rtlimages.apple.com).
    static func imageURL(storeID: String) -> URL? {
        guard storeID.range(of: #"^R[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "rtlimages.apple.com"
        components.path = "/cmc/dieter/store/4_3/\(storeID).png"
        components.percentEncodedQuery = "resize=1200:*&output-format=jpg&output-quality=80"
        return components.url
    }
}

/// Names and store numbers from Apple's public retail store list pages.
/// English names come from apple.com; Simplified Chinese names come from apple.com.cn.
actor AppleStoreDirectory {
    static let shared = AppleStoreDirectory()

    private var stores: [AppleStore] = []
    private var loadedAt: Date?
    private let session: URLSession
    private let cacheURL: URL

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "ApplePickupTracker"]
        session = URLSession(configuration: config)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheURL = caches.appendingPathComponent("apple-retail-stores.json")
    }

    func store(matching storeName: String) async -> AppleStore? {
        // Resolve the known Shenzhen branch immediately; do not make the photo
        // wait for three remote directory pages to finish loading.
        if let known = Self.shenzhenMixCStore(matching: storeName) { return known }
        await ensureLoaded()
        return Self.match(storeName, in: stores)
    }

    private static func shenzhenMixCStore(matching storeName: String) -> AppleStore? {
        let query = normalize(storeName)
        let isShenzhenMixC = query.contains("深圳万象城")
            || query.contains("shenzhenmixc")
            || query.contains("mixcshenzhen")
            || (query.contains("shenzhen") && query.contains("mixc"))
        guard isShenzhenMixC,
              let imageURL = URL(string: "https://www.apple.com/newsroom/images/environments/stores/Apple-Shenzhen-China-media-preview-storefront_Full-Bleed-Image.jpg.large.jpg") else { return nil }
        return AppleStore(id: "R761", name: "Apple MixC Shenzhen", city: "Shenzhen", imageURL: imageURL)
    }

    private func ensureLoaded() async {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 60 * 60 * 24, !stores.isEmpty { return }
        if stores.isEmpty, let cached = loadCache() {
            stores = cached
            loadedAt = Date()
        }
        let fresh = await fetchStores()
        if !fresh.isEmpty {
            stores = fresh
            loadedAt = Date()
            saveCache(fresh)
        }
    }

    private func fetchStores() async -> [AppleStore] {
        let pages = [
            "https://www.apple.com/retail/storelist/",
            "https://www.apple.com.cn/retail/storelist/",
            "https://www.apple.com/hk/retail/storelist/"
        ]
        var combined: [AppleStore] = []
        for page in pages {
            guard let url = URL(string: page) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let html = String(data: data, encoding: .utf8) else { continue }
                combined.append(contentsOf: Self.stores(inHTML: html))
            } catch {
                continue
            }
        }
        var seen = Set<String>()
        return combined.filter { seen.insert("\($0.id)|\($0.name)").inserted }
    }

    static func stores(inHTML html: String) -> [AppleStore] {
        guard let start = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex) else { return [] }
        let jsonText = String(html[start.upperBound..<end.lowerBound])
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let page = props["pageProps"] as? [String: Any],
              let list = page["storeList"] as? [[String: Any]] else { return [] }
        var stores: [AppleStore] = []
        for country in list {
            for state in country["state"] as? [[String: Any]] ?? [] {
                for item in state["store"] as? [[String: Any]] ?? [] {
                    guard let id = item["id"] as? String,
                          let name = item["name"] as? String,
                          let imageURL = AppleStore.imageURL(storeID: id) else { continue }
                    let city = (item["address"] as? [String: Any])?["city"] as? String ?? ""
                    stores.append(AppleStore(id: id, name: name, city: city, imageURL: imageURL))
                }
            }
        }
        return stores
    }

    static func match(_ storeName: String, in stores: [AppleStore]) -> AppleStore? {
        let query = normalize(storeName)
        guard query.count >= 2 else { return nil }
        var best: (store: AppleStore, score: Int)?
        for store in stores {
            let name = normalize(store.name)
            let city = normalize(store.city)
            guard name.count >= 2 else { continue }
            var score = 0
            if query == name { score = 10_000 + name.count }
            else if query.contains(name) { score = 1_000 + name.count }
            else if name.contains(query), query.count >= 3 { score = 500 + query.count }
            else if !city.isEmpty, query.contains(city), query.contains(name) { score = 800 + name.count }
            if score > (best?.score ?? 0) { best = (store, score) }
        }
        return best?.store
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "apple", with: "")
            .replacingOccurrences(of: "store", with: "")
            .replacingOccurrences(of: "零售店", with: "")
            .replacingOccurrences(of: "专卖店", with: "")
            .replacingOccurrences(of: "蘋果", with: "")
            .replacingOccurrences(of: "苹果", with: "")
        return folded.filter { $0.isLetter || $0.isNumber }
    }

    private func loadCache() -> [AppleStore]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([AppleStore].self, from: data),
              !cached.isEmpty else { return nil }
        return cached
    }

    private func saveCache(_ stores: [AppleStore]) {
        guard let data = try? JSONEncoder().encode(stores) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
