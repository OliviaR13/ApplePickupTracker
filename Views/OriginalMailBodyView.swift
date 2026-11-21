import SwiftUI
import WebKit

/// Displays the original message layout while blocking remote resources and navigation.
struct OriginalMailBodyView: UIViewRepresentable {
    let content: String
    let isHTML: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(document, baseURL: nil)
        context.coordinator.lastDocument = document
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        webView.loadHTMLString(document, baseURL: nil)
    }

    private var document: String {
        let source: String
        if isHTML {
            source = Self.sanitizedHTML(content)
        } else {
            let escaped = content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            source = "<pre>\(escaped)</pre>"
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <meta name="color-scheme" content="light dark">
          <style>
            :root { color-scheme: light dark; }
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; }
            body {
              padding: 16px;
              background: #fdfcf9;
              color: #1d1b17;
              font: 15px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
              overflow-wrap: anywhere;
              -webkit-text-size-adjust: 100%;
            }
            .mail-content { width: 100%; max-width: 100%; overflow: hidden; }
            table { max-width: 100% !important; }
            img { max-width: 100% !important; height: auto !important; }
            pre { white-space: pre-wrap; overflow-wrap: anywhere; font: inherit; }
            p { max-width: 100%; }
            a { color: #0f7f69; text-decoration: none; }
            @media (prefers-color-scheme: dark) {
              body { background: #191815; color: #efece5; }
              a { color: #3fcfa6; }
            }
          </style>
        </head>
        <body><main class="mail-content">\(source)</main></body>
        </html>
        """
    }

    private static func sanitizedHTML(_ input: String) -> String {
        var html = input
        let removals = [
            #"(?is)<script\b[^>]*>.*?</script>"#,
            #"(?is)<iframe\b[^>]*>.*?</iframe>"#,
            #"(?is)<form\b[^>]*>.*?</form>"#,
            #"(?is)<object\b[^>]*>.*?</object>"#,
            #"(?is)<embed\b[^>]*>"#,
            #"(?is)<link\b[^>]*>"#,
            #"(?is)<meta\b[^>]*>"#,
            #"(?is)<img\b(?=[^>]*\bsrc\s*=\s*["']https?://)[^>]*>"#,
            #"(?is)<img\b(?=[^>]*\bsrc\s*=\s*["']cid:)[^>]*>"#
        ]
        for pattern in removals {
            html = html.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        html = html.replacingOccurrences(
            of: #"(?i)\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            with: "",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?i)\s+href\s*=\s*["']\s*javascript:[^"']*["']"#,
            with: "",
            options: .regularExpression
        )
        return html
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastDocument = ""
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}
