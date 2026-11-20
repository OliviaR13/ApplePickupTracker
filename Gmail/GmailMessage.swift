import Foundation

struct GmailMessageList: Decodable {
    struct Message: Decodable { let id: String }
    let messages: [Message]?
}

struct GmailMessage: Decodable {
    struct Payload: Decodable {
        struct Header: Decodable { let name: String; let value: String }
        let headers: [Header]?
        let mimeType: String?
        let body: Body?
        let parts: [Payload]?
        struct Body: Decodable { let data: String? }
    }
    let id: String
    let internalDate: String?
    let snippet: String?
    let payload: Payload?

    var headerMap: [String: String] {
        Dictionary((payload?.headers ?? []).map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    var decodedText: String {
        var plainText: [String] = []
        var htmlText: [String] = []

        func walk(_ part: Payload) {
            if let data = part.body?.data,
               let decoded = Self.decodeBase64URL(data),
               let text = String(data: decoded, encoding: .utf8) {
                switch part.mimeType?.lowercased() {
                case "text/plain": plainText.append(text)
                case "text/html": htmlText.append(text)
                default: break
                }
            }
            (part.parts ?? []).forEach(walk)
        }

        if let payload { walk(payload) }
        let selected = plainText.isEmpty ? htmlText : plainText
        let body = selected.joined(separator: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return (body + "\n" + (snippet ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var receivedAt: Date {
        guard let internalDate, let milliseconds = Double(internalDate) else { return Date() }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: normalized)
    }
}
