import Foundation

struct ParsedPickupMail {
    let orderNumber: String
    let productName: String
    let storeName: String
    let pickupNote: String?
    let recognitionConfidence: Double
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

    func fetchAppleOrderMessages() async throws -> OutlookFetchResult {
        let token = try await oauth.validAccessToken()
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
        components.queryItems = [
            .init(name: "$top", value: "100"),
            .init(name: "$select", value: "id,receivedDateTime,from,subject,body"),
            .init(name: "$orderby", value: "receivedDateTime desc"),
            .init(name: "$filter", value: "receivedDateTime ge \\(ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -365, to: Date())!))")
        ]
        var nextURL: URL? = components.url
        var parsed: [ParsedPickupMail] = []
        var scanned = 0
        var appleCount = 0

        while let url = nextURL, scanned < 1000 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
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
                let content = AppleMailFields.plain((message.subject ?? "") + "\\n" + (message.body?.content ?? ""))
                guard let order = AppleMailFields.normalizedOrderNumber(in: content) else { continue }
                let status = PickupStatus.detect(in: content)
                guard status != .unknown else { continue }
                let product = AppleMailFields.productName(from: content)
                let store = AppleMailFields.storeName(from: content)
                let confidence = AppleMailFields.confidence(orderNumber: order, productName: product, storeName: store, status: status)
                let date = message.receivedDateTime.flatMap { value -> Date? in
                    let fractional = ISO8601DateFormatter()
                    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
                } ?? Date()
                parsed.append(ParsedPickupMail(orderNumber: order, productName: product, storeName: store,
                                               pickupNote: AppleMailFields.pickupNote(from: content),
                                               recognitionConfidence: confidence, status: status,
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
}
