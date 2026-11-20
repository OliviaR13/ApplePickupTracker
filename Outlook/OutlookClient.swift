import Foundation

struct ParsedPickupMail {
    let orderNumber: String
    let productName: String
    let storeName: String
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
        struct Address: Decodable { let address: String? }
        struct Email: Decodable { let address: Address? }
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

private extension ISO8601DateFormatter {\n    static let withFractionalSeconds: ISO8601DateFormatter = {\n        let formatter = ISO8601DateFormatter()\n        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]\n        return formatter\n    }()\n}\n\nfinal class OutlookClient {
    private let oauth: OutlookOAuth
    init(oauth: OutlookOAuth) { self.oauth = oauth }

    func fetchAppleOrderMessages() async throws -> OutlookFetchResult {
        let token = try await oauth.validAccessToken()
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
        components.queryItems = [
            .init(name: "$top", value: "100"),
            .init(name: "$select", value: "id,receivedDateTime,from,subject,body"),
            .init(name: "$orderby", value: "receivedDateTime desc"),
            .init(name: "$filter", value: "receivedDateTime ge \(ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -365, to: Date())!))")
        ]
        var nextURL: URL? = components.url
        var parsed: [ParsedPickupMail] = []
        var scanned = 0
        var appleCount = 0

        while let url = nextURL, scanned < 1000 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue('outlook.body-content-type="text"', forHTTPHeaderField: "Prefer")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response, data: data)
            let page = try JSONDecoder().decode(GraphMessagePage.self, from: data)
            scanned += page.value.count
            for message in page.value {
                let sender = message.from?.emailAddress?.address?.lowercased() ?? ""
                guard Self.isAppleSender(sender) else { continue }
                appleCount += 1
                let content = (message.subject ?? "") + "\n" + (message.body?.content ?? "")
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                guard let order = Self.firstMatch(#"(?i)(?:order\s*(?:number|#|no\.?)[\s:：#]*)\s*([A-Z0-9-]{8,})|\b(W\d{8,})\b"#, in: content) else { continue }
                let status = PickupStatus.detect(in: content)
                guard status != .unknown else { continue }
                let date = message.receivedDateTime.flatMap { value -> Date? in
                    ISO8601DateFormatter().date(from: value)
                    ?? ISO8601DateFormatter.withFractionalSeconds.date(from: value)
                } ?? Date()
                parsed.append(ParsedPickupMail(orderNumber: order, productName: Self.productName(from: content),
                                               storeName: Self.storeName(from: content), status: status,
                                               messageID: message.id, date: date))
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

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
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

    private static func storeName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("Apple Store") }) {
            return lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let index = lines.firstIndex(where: { $0.contains("Apple") && ($0.contains("店") || $0.contains("零售店")) }) {
            return lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Store Pickup"
    }
}
