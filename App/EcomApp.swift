import UIKit
import SwiftUI
import WebKit

@main
struct EcomApp: App {
    @StateObject private var web = WebModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                WebView(model: web)
                if web.failed {
                    OfflineView { web.reload() }
                }
            }
            .onOpenURL { url in
                web.load(EcomLinks.siteURL(fromDeepLink: url))
            }
        }
    }
}

/// 연결이 안 될 때 보이는 화면.
struct OfflineView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("ecom 에 연결하지 못했습니다")
                .font(.headline)
            Text("인터넷 연결을 확인한 뒤 다시 시도해 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("다시 시도", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0, green: 80 / 255, blue: 52 / 255))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

/// 웹 화면 하나를 앱 전체가 함께 쓴다(위젯으로 열어도 같은 화면에 주소만 바꿔 넣는다).
final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var failed = false
    let webView: WKWebView
    private var started = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // 사이트가 앱 안에서 열렸는지 알 수 있게 표시를 붙인다(Safari 표시는 그대로 둔다).
        config.applicationNameForUserAgent = "Mobile/15E148 Safari/604.1 EcomiOS/0.1"
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulled(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        load(EcomLinks.site)
    }

    func load(_ url: URL) {
        started = true
        failed = false
        webView.load(URLRequest(url: url))
    }

    func reload() {
        failed = false
        if webView.url == nil {
            load(EcomLinks.site)
        } else {
            webView.reload()
        }
    }

    @objc private func pulled(_ sender: UIRefreshControl) {
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
    }

    // ecom 밖 주소는 Safari 로 연다.
    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        if isMainFrame, let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                if url.host?.lowercased() != EcomLinks.host {
                    UIApplication.shared.open(url)
                    return decisionHandler(.cancel)
                }
            } else if scheme != "about" && scheme != "blob" && scheme != "data" {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
        }
        decisionHandler(.allow)
    }

    // 새 창(target=_blank)으로 여는 링크.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if url.host?.lowercased() == EcomLinks.host {
                webView.load(action.request)
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        failed = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        markFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        markFailed(error)
    }

    private func markFailed(_ error: Error) {
        let ns = error as NSError
        // 다른 주소로 넘어가며 취소된 것은 실패가 아니다.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        failed = true
    }

    // 웹 화면이 메모리 부족으로 꺼지면 다시 띄운다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeUIView(context: Context) -> WKWebView {
        model.startIfNeeded()
        return model.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
