import SwiftUI
import UIKit

@MainActor
enum StoreImageLoader {
    private static let cache = NSCache<NSURL, UIImage>()
    private static let session: URLSession = {
        let storage = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        let config = URLSessionConfiguration.default
        config.urlCache = storage
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    static func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}

struct StorePhotoView: View {
    let storeName: String
    var height: CGFloat = 56
    var cornerRadius: CGFloat = 14

    @State private var image: UIImage?
    @State private var resolved = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: height, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(resolved && image == nil ? "暂无\(storeName)店面照片" : "\(storeName)店面")
        .task(id: storeName) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .secondarySystemFill)
            Image(systemName: resolved ? "building.2" : "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func load() async {
        resolved = false
        image = nil
        guard let store = await AppleStoreDirectory.shared.store(matching: storeName) else {
            resolved = true
            return
        }
        image = await StoreImageLoader.image(for: store.imageURL)
        resolved = true
    }
}

struct StorePhotoBanner: View {
    let storeName: String
    @State private var image: UIImage?
    @State private var resolved = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color.blue.opacity(0.55), Color.cyan.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 8) {
                            Image(systemName: resolved ? "building.2.fill" : "photo")
                                .font(.largeTitle)
                            Text(resolved ? "暂无店面照片" : "正在查找店面")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipped()

            Text(storeName)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlass(in: Capsule())
                .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: storeName) { await load() }
    }

    private func load() async {
        resolved = false
        image = nil
        guard let store = await AppleStoreDirectory.shared.store(matching: storeName) else {
            resolved = true
            return
        }
        image = await StoreImageLoader.image(for: store.imageURL)
        resolved = true
    }
}
