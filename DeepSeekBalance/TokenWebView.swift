import SwiftUI
import WebKit

// MARK: - 安全登录：提取候选 Token，并通过 DeepSeek API 验证后保存

private let extractTokenJS = """
(function() {
  var result = [];
  function add(key, value) {
    if (typeof value !== 'string' || value.length === 0) return;
    result.push({ key: String(key || ''), value: value });
  }
  function scanStorage(storage, prefix) {
    try {
      for (var i = 0; i < storage.length; i++) {
        var key = storage.key(i);
        if (/token|auth|session|credential/i.test(key)) add(prefix + ':' + key, storage.getItem(key));
      }
    } catch(e) {}
  }
  try {
    var cookies = document.cookie.split('; ');
    for (var i = 0; i < cookies.length; i++) {
      var pair = cookies[i].split('=');
      add('cookie:' + pair[0], decodeURIComponent(pair.slice(1).join('=')));
    }
    scanStorage(localStorage, 'localStorage');
    scanStorage(sessionStorage, 'sessionStorage');
    if (window.__NEXT_DATA__ && window.__NEXT_DATA__.props && window.__NEXT_DATA__.props.pageProps) {
      var p = window.__NEXT_DATA__.props.pageProps;
      if (p.userToken) add('next:userToken', String(p.userToken));
    }
    if (window.__INITIAL_STATE__ && window.__INITIAL_STATE__.user && window.__INITIAL_STATE__.user.token) {
      add('initial:token', String(window.__INITIAL_STATE__.user.token));
    }
  } catch(e) {}
  return result;
})();
"""

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
        private var isValidating = false
        private var attemptedCandidates = Set<String>()
        private var pollingTimer: Timer?

        init(onComplete: @escaping (String) -> Void) {
            self.onComplete = onComplete
        }

        @objc func dismiss() {
            stopObserving()
            nav?.dismiss(animated: true)
        }

        private func tryExtractToken() {
            guard !hasFoundToken, !isValidating, let wv = webView else { return }
            guard let host = wv.url?.host, host == "platform.deepseek.com" || host.hasSuffix(".deepseek.com") else {
                return
            }

            wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.hasFoundToken else { return }
                var candidates: [String] = []
                for cookie in cookies {
                    let domainOK = cookie.domain == "platform.deepseek.com" || cookie.domain.hasSuffix(".platform.deepseek.com") || cookie.domain.hasSuffix(".deepseek.com")
                    if !domainOK { continue }
                    candidates.append(contentsOf: DeepSeekTokenCandidate.values(key: cookie.name, raw: cookie.value))
                }

                guard !self.hasFoundToken else { return }
                wv.evaluateJavaScript(extractTokenJS) { [weak self] result, _ in
                    guard let self = self, !self.hasFoundToken else { return }
                    if let items = result as? [[String: Any]] {
                        for item in items {
                            guard let key = item["key"] as? String, let raw = item["value"] as? String else { continue }
                            candidates.append(contentsOf: DeepSeekTokenCandidate.values(key: key, raw: raw))
                        }
                    }
                    self.validate(candidates)
                }
            }
        }

        private func validate(_ candidates: [String]) {
            let untried = candidates.filter { attemptedCandidates.insert($0).inserted }
            guard !untried.isEmpty else { return }
            isValidating = true
            nav?.topViewController?.navigationItem.prompt = "正在验证登录状态…"
            Task { [weak self] in
                guard let self else { return }
                for candidate in untried {
                    if (try? await DeepSeekAPI.shared.fetchSummary(token: candidate)) != nil {
                        await MainActor.run { self.found(candidate) }
                        return
                    }
                }
                await MainActor.run {
                    self.isValidating = false
                    self.nav?.topViewController?.navigationItem.prompt = "登录成功后会自动保存 Token"
                }
            }
        }

        private func found(_ token: String) {
            guard !hasFoundToken else { return }
            hasFoundToken = true
            stopObserving()
            DispatchQueue.main.async {
                self.onComplete(token)
                self.nav?.dismiss(animated: true)
            }
        }

        private func startPolling() {
            guard pollingTimer == nil else { return }
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tryExtractToken()
            }
            tryExtractToken()
        }

        private func stopObserving() {
            pollingTimer?.invalidate()
            pollingTimer = nil
            if let ds = dataStore { ds.httpCookieStore.remove(self) }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            tryExtractToken()
        }

        // MARK: - 导航策略

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

        // MARK: - 页面加载完成

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasFoundToken else { return }
            startPolling()
        }
    }
}
