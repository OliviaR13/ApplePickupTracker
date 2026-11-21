import Foundation

struct ParsedPickupMail {
    let orderNumber: String
    let productName: String
    let storeName: String
    let pickupNote: String?
    let metadata: AppleOrderMetadata
    let pickupQRCode: String?
    let walletPassURL: String?
    let status: PickupStatus
    let messageID: String
    let date: Date
}

struct OutlookFetchResult {
    let messages: [ParsedPickupMail]
    let scannedCount: Int
    let appleSenderCount: Int
}

private struct GraphMessagePage: Decodable {
    struct Message: Decodable {
        struct Email: Decodable { let address: String? }
        struct Sender: Decodable { let emailAddress: Email? }
        struct Body: Decodable { let content: String?; let contentType: String? }
        let id: String
        let subject: String?
        let receivedDateTime: String?
        let from: Sender?
        let body: Body?
    }
    let value: [Message]
    let nextLink: String?
    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}


private struct GraphAttachmentPage: Decodable {
    struct Attachment: Decodable {
        let name: String?
        let contentType: String?
        let contentBytes: String?
        let contentId: String?
        let isInline: Bool?
    }
    let value: [Attachment]
}

final class OutlookClient {
    private let oauth: OutlookOAuth
    init(oauth: OutlookOAuth) { self.oauth = oauth }

    private nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()
    private nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let orderRegex = try? NSRegularExpression(
        pattern: #"(?i)(?:order\s*(?:number|#|no\.?)[\s:：#]*)\s*([A-Z0-9-]{8,})|\b(W\d{8,})\b"#)

    /// - Parameter since: only fetch mail received after this date. Defaults to the last 365 days.
    func fetchAppleOrderMessages(since: Date? = nil) async throws -> OutlookFetchResult {
        let windowStart = since ?? Calendar.current.date(byAdding: .day, value: -365, to: Date())!
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
        components.queryItems = [
            .init(name: "$top", value: "100"),
            .init(name: "$select", value: "id,receivedDateTime,from,subject,body"),
            .init(name: "$orderby", value: "receivedDateTime desc"),
            .init(name: "$filter", value: "receivedDateTime ge \(Self.isoPlain.string(from: windowStart))")
        ]
        var nextURL: URL? = components.url
        var parsed: [ParsedPickupMail] = []
        var scanned = 0
        var appleCount = 0

        while let url = nextURL, scanned < 1000 {
            // Fetch per page: validAccessToken() refreshes when needed, so long scans don't use an expired token.
            let token = try await oauth.validAccessToken()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("outlook.body-content-type=\"html\"", forHTTPHeaderField: "Prefer")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response, data: data)
            let page = try JSONDecoder().decode(GraphMessagePage.self, from: data)
            scanned += page.value.count
            for message in page.value {
                let sender = message.from?.emailAddress?.address?.lowercased() ?? ""
                guard Self.isAppleSender(sender) else { continue }
                appleCount += 1
                let content = AppleMailFields.plain((message.subject ?? "") + "\n" + (message.body?.content ?? ""))

                // Apple Gift Cards delivered by email are not physical store-pickup orders.
                // Require both the digital-delivery marker and a gift-card product marker.
                if Self.isEmailGiftCard(content) { continue }

                guard let order = Self.firstMatch(Self.orderRegex, in: content) else { continue }
                let status = PickupStatus.detect(in: content)
                guard status != .unknown else { continue }
                let date = message.receivedDateTime.flatMap { value in
                    Self.isoPlain.date(from: value) ?? Self.isoFractional.date(from: value)
                } ?? Date()
                let rawBody = message.body?.content ?? ""
                let assets: (qr: String?, wallet: String?)
                if status == .readyForPickup {
                    assets = await fetchPickupAssets(messageID: message.id, html: rawBody, token: token)
                } else {
                    assets = (nil, nil)
                }
                parsed.append(ParsedPickupMail(orderNumber: order, productName: Self.productName(from: content),
                                               storeName: AppleMailFields.storeName(from: content),
                                               pickupNote: AppleMailFields.pickupNote(from: content),
                                               metadata: AppleMailFields.orderMetadata(from: content),
                                               pickupQRCode: assets.qr, walletPassURL: assets.wallet,
                                               status: status, messageID: message.id, date: date))
            }
            nextURL = page.nextLink.flatMap(URL.init(string:))
        }
        return OutlookFetchResult(messages: parsed.sorted { $0.date < $1.date },
                                  scannedCount: scanned, appleSenderCount: appleCount)
    }


    /// Extracts the pickup QR and Apple Wallet link only from ready-for-pickup messages.
    /// Outlook may expose QR images as data URIs or as inline CID file attachments.
    private func fetchPickupAssets(messageID: String, html: String, token: String) async -> (qr: String?, wallet: String?) {
        let walletURL = Self.walletPassURL(in: html)
        if let dataURI = Self.qrDataURI(in: html) {
            return (dataURI, walletURL)
        }

        guard let encodedID = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(encodedID)/attachments?$select=name,contentType,contentBytes,contentId,isInline") else {
            return (nil, walletURL)
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let page = try? JSONDecoder().decode(GraphAttachmentPage.self, from: data) else {
                return (nil, walletURL)
            }

            let referencedCID = Set(Self.cidReferences(in: html))
            let candidates = page.value.filter { attachment in
                let type = attachment.contentType?.lowercased() ?? ""
                let name = attachment.name?.lowercased() ?? ""
                let cid = attachment.contentId.map { referencedCID.contains($0) } ?? false
                return type.contains("image/") && (
                    name.contains("qr") || name.contains("barcode") || cid
                    || (attachment.isInline == true && referencedCID.isEmpty && type.contains("png"))
                )
            }
            for attachment in candidates {
                if let bytes = attachment.contentBytes, !bytes.isEmpty {
                    return (bytes, walletURL)
                }
            }
        } catch {
            // Asset extraction is optional; the order status remains useful if attachments fail.
        }
        return (nil, walletURL)
    }

    private static func qrDataURI(in html: String) -> String? {
        let qrPattern = #"(?is)<img\b(?=[^>]*\balt=["'][^"']*qr[^"']*["'])[^>]*\bsrc=["']data:image/[^;]+;base64,([A-Za-z0-9+/=]+)["']"#
        let fallbackPattern = #"(?is)<img\b[^>]*\bsrc=["']data:image/(?:png|jpeg|jpg);base64,([A-Za-z0-9+/=]+)["']"#
        for pattern in [qrPattern, fallbackPattern] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            return String(html[range])
        }
        return nil
    }

    private static func cidReferences(in html: String) -> [String] {
        let qrImagePattern = #"(?is)<img\b(?=[^>]*\balt=["'][^"']*qr[^"']*["'])[^>]*\bsrc=["']cid:([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: qrImagePattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return [String(html[range])]
        }
        guard let regex = try? NSRegularExpression(pattern: #"(?i)cid:([^"'\s>]+)"#) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    private static func walletPassURL(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<a[^>]+href=["'](https://[^"']+)["'][^>]*>.*?(?:add to apple wallet|apple wallet|加入 apple 钱包|加入 apple 錢包).*?</a>"#) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: html),
                  let url = URL(string: String(html[valueRange])),
                  let host = url.host?.lowercased(),
                  host == "apple.com" || host.hasSuffix(".apple.com") else { continue }
            return url.absoluteString
        }
        return nil
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OutlookError.tokenExchangeFailed }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            throw OutlookError.apiFailure(status: http.statusCode, message: error?["message"] as? String ?? "Microsoft Graph 请求失败")
        }
    }

    private static func isAppleSender(_ address: String) -> Bool {
        guard let domain = address.split(separator: "@").last?.lowercased() else { return false }
        return domain == "apple.com" || domain.hasSuffix(".apple.com")
    }

    private static func firstMatch(_ regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for index in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text) { return String(text[range]) }
        }
        return Range(match.range, in: text).map { String(text[$0]) }
    }

    private static func isEmailGiftCard(_ text: String) -> Bool {
        let value = text.lowercased()
        let hasGiftCard = value.contains("apple gift card") || value.contains("apple礼品卡")
            || value.contains("apple 禮品卡") || value.contains("apple giftcard")
        let isEmailDelivery = value.contains("items to be emailed")
            || value.contains("send to:") || value.contains("gift card details")
            || value.contains("电子邮件发送") || value.contains("以电子邮件发送")
        return hasGiftCard && isEmailDelivery
    }

    private static func productName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let productKeywords = ["iPhone", "MacBook", "iPad", "Apple Watch", "AirPods",
                               "Apple Pencil", "HomePod", "Apple TV", "Magic Keyboard"]
        return lines.first(where: { line in
            productKeywords.contains(where: { line.localizedCaseInsensitiveContains($0) })
        }) ?? "Apple Store Order"
    }

}
