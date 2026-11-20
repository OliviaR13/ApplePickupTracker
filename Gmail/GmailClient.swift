import Foundation

struct ParsedPickupMail {
    let orderNumber: String
    let productName: String
    let storeName: String
    let status: PickupStatus
    let messageID: String
    let date: Date
}

final class GmailClient {
    private let oauth: GmailOAuth

    init(oauth: GmailOAuth) { self.oauth = oauth }

    func fetchAppleOrderMessages() async throws -> [ParsedPickupMail] {
        let token = try await oauth.validAccessToken()
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            .init(name: "q", value: "newer_than:365d {from:(apple.com) from:(email.apple.com)} {subject:(order) subject:(pickup) subject:(ready)}"),
            .init(name: "maxResults", value: "50")
        ]
        var listRequest = URLRequest(url: components.url!)
        listRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (listData, _) = try await URLSession.shared.data(for: listRequest)
        let list = try JSONDecoder().decode(GmailMessageList.self, from: listData)
        var results: [ParsedPickupMail] = []
        for item in list.messages ?? [] {
            var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(item.id)?format=full")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let message = try JSONDecoder().decode(GmailMessage.self, from: data)
            let sender = message.headerMap["from"] ?? ""
            guard Self.isAppleSender(sender) else { continue }
            let content = (message.headerMap["subject"] ?? "") + "\n" + message.decodedText
            guard let order = Self.firstMatch(#"(?i)(?:order\s*(?:number|#|no\.?)[\s:：#]*)\s*([A-Z0-9-]{8,})|W\d{8,}"#, in: content) else { continue }
            let status = PickupStatus.detect(in: content)
            guard status != .unknown else { continue }
            results.append(ParsedPickupMail(orderNumber: order, productName: Self.productName(from: content),
                                            storeName: Self.storeName(from: content), status: status,
                                            messageID: message.id, date: message.receivedAt))
        }
        return results.sorted { $0.date < $1.date }
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
        let range = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text) }.first
        return range.map { String(text[$0]) } ?? Range(match.range, in: text).map { String(text[$0]) }
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
