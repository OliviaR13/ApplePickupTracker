import Foundation

struct ParsedPickupMail {
    let orderNumber: String
    let productName: String
    let storeName: String
    let status: PickupStatus
    let messageID: String
    let date: Date
}

struct GmailFetchResult {
    let messages: [ParsedPickupMail]
    let scannedCount: Int
    let appleSenderCount: Int
}

final class GmailClient {
    private let oauth: GmailOAuth

    init(oauth: GmailOAuth) { self.oauth = oauth }

    func fetchAppleOrderMessages() async throws -> GmailFetchResult {
        let token = try await oauth.validAccessToken()
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            .init(name: "q", value: "newer_than:365d {from:apple.com from:email.apple.com}"),
            .init(name: "maxResults", value: "100")
        ]
        var listRequest = URLRequest(url: components.url!)
        listRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        listRequest.timeoutInterval = 30
        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
        try Self.validate(listResponse, data: listData)
        let list = try JSONDecoder().decode(GmailMessageList.self, from: listData)

        var results: [ParsedPickupMail] = []
        var appleSenderCount = 0
        let candidates = list.messages ?? []

        for item in candidates {
            var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(item.id)?format=full")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response, data: data)
            let message = try JSONDecoder().decode(GmailMessage.self, from: data)
            let sender = message.headerMap["from"] ?? ""
            guard Self.isAppleSender(sender) else { continue }
            appleSenderCount += 1

            let content = (message.headerMap["subject"] ?? "") + "\n" + message.decodedText
            guard let order = Self.firstMatch(#"(?i)(?:order\s*(?:number|#|no\.?)[\s:：#]*)\s*([A-Z0-9-]{8,})|\b(W\d{8,})\b"#, in: content) else { continue }
            let status = PickupStatus.detect(in: content)
            guard status != .unknown else { continue }
            results.append(ParsedPickupMail(orderNumber: order, productName: Self.productName(from: content),
                                            storeName: Self.storeName(from: content), status: status,
                                            messageID: message.id, date: message.receivedAt))
        }
        return GmailFetchResult(messages: results.sorted { $0.date < $1.date },
                                scannedCount: candidates.count, appleSenderCount: appleSenderCount)
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GmailError.requestFailed }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            let message = error?["message"] as? String
            throw GmailError.apiFailure(status: http.statusCode, message: message ?? "Google API request failed")
        }
    }

    private static func isAppleSender(_ header: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"@([A-Za-z0-9.-]+)"#),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let range = Range(match.range(at: 1), in: header) else { return false }
        let domain = header[range].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
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
        return lines.first(where: { $0.localizedCaseInsensitiveContains("iPhone") || $0.localizedCaseInsensitiveContains("MacBook") || $0.localizedCaseInsensitiveContains("iPad") || $0.localizedCaseInsensitiveContains("Apple Watch") }) ?? "Apple Store Order"
    }

    private static func storeName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("Apple Store") }) {
            return lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Store Pickup"
    }
}

enum GmailError: LocalizedError {
    case requestFailed
    case apiFailure(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "无法连接 Gmail。请检查网络后重试。"
        case let .apiFailure(status, message):
            return "Gmail API 错误（HTTP \(status)）：\(message)"
        }
    }
}
