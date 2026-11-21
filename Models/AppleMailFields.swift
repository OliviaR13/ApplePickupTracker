import Foundation

extension PickupOrder {
    /// Store line safe to show and to match against Apple's retail list.
    /// Kept out of PickupOrder.swift because the widget target compiles that file alone.
    var recognizedStoreName: String? {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "零售店", name != "Store Pickup", !AppleMailFields.isInstruction(name) else { return nil }
        return name
    }

    var displayStoreName: String { recognizedStoreName ?? "未识别门店" }
}

enum AppleMailFields {
    /// Turns Apple HTML mail into lines. Break tags become newlines before the remaining tags are removed.
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
        return text
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

    static func storeName(from text: String) -> String {
        let rows = lines(from: text)
        let labels = ["取貨地點", "取货地点", "取貨零售店", "取货零售店", "取貨門店", "取货门店", "零售店位置", "pickup location", "store location", "pickup store"]
        for (index, line) in rows.enumerated() {
            let lower = line.lowercased()
            guard labels.contains(where: { lower.contains($0) }) else { continue }
            if let same = valueAfterLabel(line, labels: labels), isLocationValue(same) { return same }
            if index + 1 < rows.count, isLocationValue(rows[index + 1]) { return rows[index + 1] }
        }
        if let named = rows.first(where: looksLikeNamedStore) { return named }
        return "零售店"
    }

    static func pickupNote(from text: String) -> String? {
        let markers = ["訂單備妥時", "订单备妥时", "When your order is ready", "我們會向你傳送取貨指示", "我们会向你传送取货指示"]
        guard let marker = markers.first(where: { text.contains($0) }),
              let start = text.range(of: marker)?.lowerBound else { return nil }
        var note = String(text[start...])
        if let stop = note.range(of: "\n\n") { note = String(note[..<stop.lowerBound]) }
        note = note.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count >= 8 else { return nil }
        if note.count > 180 { note = String(note.prefix(180)) + "…" }
        return note
    }

    private static func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func valueAfterLabel(_ line: String, labels: [String]) -> String? {
        let lower = line.lowercased()
        guard let label = labels.first(where: { lower.contains($0.lowercased()) }),
              let range = lower.range(of: label.lowercased()) else { return nil }
        let value = String(line[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:-\t"))
        return value.isEmpty ? nil : value
    }

    private static func isLocationValue(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...40).contains(trimmed.count), !isInstruction(trimmed) else { return false }
        if trimmed.range(of: #"^W\d{6,}$"#, options: .regularExpression) != nil { return false }
        let products = ["iPhone", "iPad", "MacBook", "Apple Watch", "AirPods"]
        if products.contains(where: { trimmed.contains($0) }) { return false }
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


struct AppleOrderMetadata {
    var quantity: Int?
    var productAmount: Decimal?
    var subtotal: Decimal?
    var shippingFee: Decimal?
    var totalAmount: Decimal?
    var currencyCode: String?
    var storeAddress: String?
    var storePostalCode: String?
    var storePhone: String?
}

extension AppleMailFields {
    /// Extracts optional commercial and store fields from Apple's localized order emails.
    /// Missing fields remain nil so a later email never erases previously parsed details.
    static func orderMetadata(from text: String) -> AppleOrderMetadata {
        let rows = lines(from: text)
        var result = AppleOrderMetadata()

        result.quantity = firstCapture(#"(?i)(?:数量|qty|quantity)\s*[:：]?\s*(\d{1,3})"#, in: text)
            .flatMap(Int.init)

        let moneyPattern = #"(?i)(RMB|CNY|HKD|USD|AUD|CAD|SGD|EUR|GBP|JPY|[$€£¥])\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#
        let allMoney = rows.enumerated().compactMap { index, line -> (Int, String, Decimal, String)? in
            guard let match = firstMoney(in: line, pattern: moneyPattern) else { return nil }
            return (index, match.currency, match.amount, line)
        }
        result.currencyCode = allMoney.first?.1

        if let quantityIndex = rows.firstIndex(where: {
            $0.range(of: #"(?i)(数量|qty|quantity)\s*[:：]?\s*\d+"#, options: .regularExpression) != nil
        }), let itemMoney = allMoney.first(where: { $0.0 > quantityIndex }) {
            result.productAmount = itemMoney.2
        } else {
            result.productAmount = allMoney.first?.2
        }

        result.subtotal = amount(afterAny: ["小计", "商品小计", "subtotal"], rows: rows, pattern: moneyPattern)
            ?? result.productAmount
        result.shippingFee = amount(afterAny: ["配送费", "送货费", "免费送货", "免费配送", "shipping", "delivery"], rows: rows, pattern: moneyPattern)
        result.totalAmount = amount(afterAny: ["订单总计", "订单总额", "订单合计", "order total"], rows: rows, pattern: moneyPattern)
            ?? allMoney.last?.2

        let storeLabels = ["取货零售店", "取貨零售店", "取货门店", "取貨門店", "取货地点", "取貨地點",
                           "pickup location", "store pickup location", "pickup store"]
        if let labelIndex = rows.firstIndex(where: { row in
            storeLabels.contains(where: { row.localizedCaseInsensitiveContains($0) })
        }) {
            var addressRows: [String] = []
            let start = labelIndex + 1
            if start < rows.count {
                for row in rows[start...] {
                    let lower = row.lowercased()
                    if lower.contains("营业时间") || lower.contains("營業時間")
                        || lower.contains("opening hours") || lower.contains("store hours")
                        || lower.contains("路线") || lower.contains("路線")
                        || lower.contains("directions") || lower.contains("取货政策")
                        || lower.contains("取貨政策") || lower.contains("pickup policy")
                        || lower.contains("问题") || lower.contains("questions") { break }
                    if isPhoneLine(row) {
                        result.storePhone = normalizedPhone(row)
                        break
                    }
                    if row == AppleMailFields.storeName(from: text) { continue }
                    if row.range(of: #"\b\d{5,6}\b"#, options: .regularExpression) != nil {
                        result.storePostalCode = firstCapture(#"\b(\d{5,6})\b"#, in: row)
                    }
                    if addressRows.count < 5 { addressRows.append(row) }
                }
            }
            let address = addressRows.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !address.isEmpty { result.storeAddress = address }
        }
        return result
    }

    private static func amount(afterAny labels: [String], rows: [String], pattern: String) -> Decimal? {
        for (index, row) in rows.enumerated() where labels.contains(where: {
            row.localizedCaseInsensitiveContains($0)
        }) {
            let candidates = rows[index...].prefix(3)
            for candidate in candidates {
                if let money = firstMoney(in: candidate, pattern: pattern) { return money.amount }
            }
        }
        return nil
    }

    private static func firstMoney(in text: String, pattern: String) -> (currency: String, amount: Decimal)? {
        guard let currencyAndAmount = firstCaptureGroups(pattern, in: text), currencyAndAmount.count == 2 else { return nil }
        let rawCurrency = currencyAndAmount[0]
        let rawAmount = currencyAndAmount[1].replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: rawAmount, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let currency: String
        switch rawCurrency.uppercased() {
        case "RMB", "CNY", "¥": currency = "CNY"
        case "HKD": currency = "HKD"
        case "USD", "$": currency = "USD"
        case "AUD": currency = "AUD"
        case "CAD": currency = "CAD"
        case "SGD": currency = "SGD"
        case "EUR", "€": currency = "EUR"
        case "GBP", "£": currency = "GBP"
        case "JPY": currency = "JPY"
        default: currency = rawCurrency.uppercased()
        }
        return (currency, amount)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        firstCaptureGroups(pattern, in: text)?.first
    }

    private static func firstCaptureGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func isPhoneLine(_ row: String) -> Bool {
        let digits = row.filter(\.isNumber)
        return digits.count >= 8 && digits.count <= 15
            && (row.contains("+") || row.contains("-") || row.contains("(") || row.contains(")") || digits.count >= 10)
    }

    private static func normalizedPhone(_ row: String) -> String {
        row.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
