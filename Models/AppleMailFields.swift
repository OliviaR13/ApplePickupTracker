import Foundation

extension PickupOrder {
    /// Store line safe to show and to match against Apple's retail list.
    var recognizedStoreName: String? {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "零售店", name != "Store Pickup", !AppleMailFields.isInstruction(name) else { return nil }
        return name
    }

    var displayStoreName: String { recognizedStoreName ?? "未识别门店" }
}

enum AppleMailFields {
    private static let storeLabels = [
        "取貨地點", "取货地点", "取貨零售店", "取货零售店", "取貨門店", "取货门店",
        "零售店位置", "pickup location", "store location", "pickup store"
    ]
    private static let productKeywords = ["iPhone", "iPad", "MacBook", "Apple Watch", "AirPods", "Mac mini", "iMac", "Apple TV"]

    /// Converts Apple HTML messages to readable text while retaining meaningful line boundaries.
    static func plain(_ raw: String) -> String {
        var text = raw
        let breaks = ["<br />", "<br/>", "<br>", "</p>", "</div>", "</tr>", "</li>", "</h1>", "</h2>", "</h3>", "</td>"]
        for token in breaks {
            text = text.replacingOccurrences(of: token, with: "\n", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return text.replacingOccurrences(of: "\r", with: "")
    }

    static func normalizedOrderNumber(in text: String) -> String? {
        let patterns = [
            #"(?i)订单\s*(?:编号|号码|号)\s*[：:#]?\s*(W\d{8,})"#,
            #"(?i)order\s*(?:number|#|no\.?)\s*[：:#]?\s*([A-Z0-9-]{8,})"#,
            #"\b(W\d{8,})\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            if let swiftRange = Range(range, in: text) {
                return String(text[swiftRange]).uppercased()
            }
        }
        return nil
    }

    static func productName(from text: String) -> String {
        let rows = lines(from: text)
        for line in rows {
            guard !isInstruction(line), line.count <= 100 else { continue }
            if let keyword = productKeywords.first(where: { line.localizedCaseInsensitiveContains($0) }) {
                let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: " •·-–—|\t"))
                if cleaned.count >= keyword.count { return cleaned }
            }
        }
        return "Apple Store Order"
    }

    static func storeName(from text: String) -> String {
        let rows = lines(from: text)
        for (index, line) in rows.enumerated() {
            guard storeLabels.contains(where: { line.localizedCaseInsensitiveContains($0) }) else { continue }
            if let same = valueAfterLabel(line), isLocationValue(same) { return same }
            if index + 1 < rows.count, isLocationValue(rows[index + 1]) { return rows[index + 1] }
        }
        if let named = rows.first(where: looksLikeNamedStore) { return named }
        return "零售店"
    }

    static func pickupNote(from text: String) -> String? {
        let markers = ["訂單備妥時", "订单备妥时", "When your order is ready", "我們會向你傳送取貨指示", "我们会向你传送取货指示"]
        guard let marker = markers.first(where: { text.localizedCaseInsensitiveContains($0) }),
              let start = text.range(of: marker, options: .caseInsensitive)?.lowerBound else { return nil }
        var note = String(text[start...])
        if let stop = note.range(of: "\n\n") { note = String(note[..<stop.lowerBound]) }
        note = note.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count >= 8 else { return nil }
        return note.count > 180 ? String(note.prefix(180)) + "…" : note
    }

    /// Heuristic quality score, not a guarantee that Apple's message is genuine.
    static func confidence(orderNumber: String, productName: String, storeName: String, status: PickupStatus) -> Double {
        var score = 0.35
        if orderNumber.range(of: #"^W\d{8,}$"#, options: .regularExpression) != nil { score += 0.25 }
        else if orderNumber.count >= 8 { score += 0.15 }
        if productName != "Apple Store Order" { score += 0.20 }
        if storeName != "零售店" && !isInstruction(storeName) { score += 0.15 }
        if status != .unknown { score += 0.05 }
        return min(score, 1)
    }

    static func isInstruction(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 48 { return true }
        let markers = [
            "訂單備妥", "订单备妥", "我們會向你", "我们会向你", "取貨指示", "取货指示",
            "Specialist", "如何讓我們", "如何让我们", "請瀏覽", "请浏览",
            "尋找零售店", "寻找零售店", "最新資訊", "最新资讯",
            "when your order is ready", "pickup instructions", "let us know you"
        ]
        return markers.contains { trimmed.localizedCaseInsensitiveContains($0) }
    }

    private static func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func valueAfterLabel(_ line: String) -> String? {
        let lower = line.lowercased()
        guard let label = storeLabels.first(where: { lower.contains($0.lowercased()) }),
              let range = lower.range(of: label.lowercased()) else { return nil }
        let value = String(line[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:-\t"))
        return value.isEmpty ? nil : value
    }

    private static func isLocationValue(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...40).contains(trimmed.count), !isInstruction(trimmed) else { return false }
        if trimmed.range(of: #"^W\d{6,}$"#, options: .regularExpression) != nil { return false }
        if productKeywords.contains(where: { trimmed.localizedCaseInsensitiveContains($0) }) { return false }
        return true
    }

    private static func looksLikeNamedStore(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLocationValue(trimmed) else { return false }
        let lower = trimmed.lowercased()
        if lower == "apple" || lower == "apple store" { return false }
        if lower.hasPrefix("apple ") { return true }
        let hints = ["店", "廣場", "广场", "中心", "mall", "plaza", "centre", "center", "ifc"]
        return hints.contains { lower.contains($0) }
    }
}
