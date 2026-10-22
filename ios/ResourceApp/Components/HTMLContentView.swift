import SwiftUI
import UIKit
import WebKit

/// 用 WKWebView 渲染后台文章 HTML，自动适配深色模式与图片宽度。
struct HTMLContentView: UIViewRepresentable {
    let html: String
    var baseURL: URL? = AppConfig.shared.baseURL

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let document = buildDocument()
        guard context.coordinator.lastDocument != document else { return }

        context.coordinator.lastDocument = document
        webView.loadHTMLString(document, baseURL: baseURL)
    }

    private func buildDocument() -> String {
        let isDark = colorScheme == .dark
        let background = isDark ? "#0b1220" : "#ffffff"
        let foreground = isDark ? "#e5e7eb" : "#1f2937"
        let muted = isDark ? "#9ca3af" : "#6b7280"

        let css = """
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            padding: 18px 18px 32px 18px;
            background: \(background);
            color: \(foreground);
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif;
            font-size: 16px;
            line-height: 1.85;
            -webkit-text-size-adjust: 100%;
            word-break: break-word;
        }
        p { margin: 0 0 14px 0; }
        h1, h2, h3, h4 { line-height: 1.4; margin: 22px 0 12px 0; }
        h1 { font-size: 24px; }
        h2 { font-size: 20px; }
        h3 { font-size: 18px; }
        a { color: #0aa06e; text-decoration: none; }
        img, video { max-width: 100%; height: auto; border-radius: 12px; display: block; margin: 10px 0; }
        pre, code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            background: rgba(127, 127, 127, 0.12);
            border-radius: 8px;
            padding: 2px 5px;
            font-size: 14px;
        }
        pre { padding: 12px; overflow-x: auto; }
        pre code { padding: 0; background: transparent; }
        blockquote {
            margin: 0 0 14px 0;
            padding: 2px 0 2px 14px;
            border-left: 3px solid #0aa06e;
            color: \(muted);
        }
        ul, ol { padding-left: 22px; margin: 0 0 14px 0; }
        table { width: 100%; border-collapse: collapse; margin: 12px 0; }
        th, td { border: 1px solid rgba(127, 127, 127, 0.25); padding: 7px 8px; text-align: left; }
        hr { border: none; border-top: 1px solid rgba(127, 127, 127, 0.25); margin: 22px 0; }
        </style>
        """

        return """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            \(css)
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastDocument: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
