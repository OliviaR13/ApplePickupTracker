import Foundation

struct ParsedPickupMail {
    let orderNumber: String
    let productName: String
    let storeName: String
    let pickupNote: String?
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
            request.setValue("outlook.body-content-type=\"text\"", forHTTPHeaderField: "Prefer")
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
                guard let order = Self.firstMatch(Self.orderRegex, in: content) else { continue }
                let status = PickupStatus.detect(in: content)
                guard status != .unknown else { continue }
                let date = message.receivedDateTime.flatMap { value in
                    Self.isoPlain.date(from: value) ?? Self.isoFractional.date(from: value)
                } ?? Date()
                parsed.append(ParsedPickupMail(orderNumber: order, productName: Self.productName(from: content),
                                               storeName: AppleMailFields.storeName(from: content),
                                               pickupNote: AppleMailFields.pickupNote(from: content),
                                               status: status, messageID: message.id, date: date))
            }
            nextURL = page.nextLink.flatMap(URL.init(string:))
        }
        return OutlookFetchResult(messages: parsed.sorted { $0.date < $1.date },
                                  scannedCount: scanned, appleSenderCount: appleCount)
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

    private static func productName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return lines.first(where: { line in
            ["iPhone", "MacBook", "iPad", "Apple Watch"].contains(where: { keyword in
                line.localizedCaseInsensitiveContains(keyword)
            })
        }) ?? "Apple Store Order"
    }

}
