import SwiftUI
import SwiftspringKit

#if canImport(WebKit)
import WebKit

public struct HTMLMessageView: View {
    public let html: String

    public init(html: String) {
        self.html = html
    }

    public var body: some View {
        HTMLWebView(html: Self.wrap(html))
            .background(Color.clear)
    }

    private static func wrap(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; font-src data:;">
        <style>
          :root { color-scheme: light dark; }
          body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 15px; line-height: 1.45; margin: 0; padding: 0; word-wrap: break-word; }
          img { max-width: 100%; height: auto; }
          a { color: #0B57D0; }
          blockquote { border-left: 3px solid #ccc; margin-left: 0; padding-left: 12px; color: #666; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

#if os(macOS)
struct HTMLWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
#else
struct HTMLWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
#endif
#else
public struct HTMLMessageView: View {
    public let html: String
    public init(html: String) { self.html = html }
    public var body: some View {
        Text(html)
    }
}
#endif
