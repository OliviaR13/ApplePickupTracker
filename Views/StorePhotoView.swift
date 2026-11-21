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

    /// Looks the store up in Apple's retail directory and loads its hero photo.
    static func image(forStoreName storeName: String?) async -> UIImage? {
        guard let storeName, let store = await AppleStoreDirectory.shared.store(matching: storeName) else { return nil }
        return await image(for: store.imageURL)
    }
}

struct ProductThumbnailView: View {
    let imageURL: String?
    var size: CGFloat = 58
    var cornerRadius: CGFloat = 14

    @State private var image: UIImage?
    @State private var resolved = false

    private var productURL: URL? {
        guard let imageURL, let url = URL(string: imageURL),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host.hasSuffix("apple.com"),
              url.path.contains("/is/") else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .transition(.opacity)
            } else {
                Image(systemName: resolved ? "shippingbox" : "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
        .accessibilityLabel(image == nil ? "商品图片暂不可用" : "订单商品图片")
        .task(id: imageURL) {
            resolved = false
            image = nil
            guard let url = productURL else { resolved = true; return }
            let loaded = await StoreImageLoader.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            resolved = true
        }
    }
}

struct StorePhotoView: View {
    let storeName: String?
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
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(width: height, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityLabel(image == nil ? "暂无店面照片" : "\(storeName ?? "门店")店面")
        .task(id: storeName) {
            resolved = false
            image = nil
            let loaded = await StoreImageLoader.image(forStoreName: storeName)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            resolved = true
        }
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
}

struct StorePhotoBanner: View {
    let storeName: String?
    @State private var image: UIImage?
    @State private var resolved = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
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

            Text(storeName ?? "取货门店")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlass(in: Capsule())
                .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: storeName) {
            resolved = false
            image = nil
            let loaded = await StoreImageLoader.image(forStoreName: storeName)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            resolved = true
        }
    }
}
