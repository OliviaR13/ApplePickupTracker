import Foundation

enum SyncErrorText {
    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "网络连接中断，请检查网络后再试。"
            case .timedOut:
                return "连接超时，请稍后再试。"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "无法连接服务器，请稍后再试。"
            default:
                return "网络异常，请稍后再试。"
            }
        }
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("network connection was lost") || lower.contains("internet connection appears to be offline") {
            return "网络连接中断，请检查网络后再试。"
        }
        if lower.contains("timed out") { return "连接超时，请稍后再试。" }
        if raw.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil { return raw }
        return "同步没有完成，请稍后再试。"
    }
}
