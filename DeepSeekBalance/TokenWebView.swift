import SwiftUI
import WebKit

// MARK: - 安全登录：只从 platform.deepseek.com 提取 userToken

struct TokenLoginView: UIViewControllerRepresentable {
    var onComplete: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let config = WKWebViewConfiguration()
        let dataStore = WKWebsiteDataStore.default()
        config.websiteDataStore = dataStore

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"

        context.coordinator.webView = webView
        context.coordinator.dataStore = dataStore

        // 监听 Cookie 变化
        dataStore.httpCookieStore.add(context.coordinator)

        let vc = UIViewController()
        vc.view = webView

        // 只加载 platform.deepseek.com/login
        if let url = URL(string: "https://platform.deepseek.com/login") {
            webView.load(URLRequest(url: url))
        }

        let nav = UINavigationController(rootViewController: vc)
        vc.navigationItem.title = "登录 DeepSeek"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "关闭", style: .done,
            target: context.coordinator, action: #selector(Coordinator.dismiss)
        )
        context.coordinator.nav = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let onComplete: (String) -> Void
        weak var webView: WKWebView?
        weak var nav: UINavigationController?
        var dataStore: WKWebsiteDataStore?
        private var hasFoundToken = false

        init(onComplete: @escaping (String) -> Void) {
            self.onComplete = onComplete
        }

        @objc func dismiss() {
            if let ds = dataStore { ds.httpCookieStore.remove(self) }
            nav?.dismiss(animated: true)
        }

        // MARK: - Cookie 变更监听（只读取 userToken）

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !hasFoundToken else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                for cookie in cookies where cookie.name == "userToken" && (cookie.domain == "platform.deepseek.com" || cookie.domain.hasSuffix(".platform.deepseek.com")) {
                    let raw = cookie.value.removingPercentEncoding ?? cookie.value
                    // JSON: {"value":"actual_token","__version":"0"}
                    if let data = raw.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let token = json["value"] as? String, !token.isEmpty {
                        self.found(token)
                        return
                    }
                    // fallback: 直接使用原始值
                    self.found(raw)
                }
            }
        }

        private func found(_ token: String) {
            hasFoundToken = true
            if let ds = dataStore { ds.httpCookieStore.remove(self) }
            DispatchQueue.main.async {
                self.onComplete(token)
                self.nav?.dismiss(animated: true)
            }
        }

        // MARK: - 页面加载完成后也检查一次

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 只允许 DeepSeek 域名
            if let host = navigationAction.request.url?.host {
                let allowed = host == "platform.deepseek.com" || host.hasSuffix(".deepseek.com")
                if allowed || navigationAction.navigationType == .backForward {
                    decisionHandler(.allow)
                    return
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasFoundToken else { return }

            // 只检查 userToken cookie
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                for cookie in cookies where cookie.name == "userToken" && (cookie.domain == "platform.deepseek.com" || cookie.domain.hasSuffix(".platform.deepseek.com")) {
                    let raw = cookie.value.removingPercentEncoding ?? cookie.value
                    if let data = raw.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let token = json["value"] as? String {
                        self.found(token)
                        return
                    }
                    self.found(raw)
                }
            }
        }
    }
}
