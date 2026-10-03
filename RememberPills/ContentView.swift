import SwiftUI
import WebKit
import Network
import UIKit

private let dashboardURL = URL(string: "https://www.rememberpills.com/dashboard.php")!
private let rememberPillsHosts: Set<String> = ["www.rememberpills.com", "rememberpills.com"]

struct ContentView: View {
    @StateObject private var model = WebViewModel()
    @State private var showingShare = false

    var body: some View {
        VStack(spacing: 0) {
            if !model.isOnline {
                Text("No internet connection. RememberPills.com will reconnect automatically.")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.18))
            }

            WebContainer(webView: model.webView)

            Divider()

            HStack(spacing: 0) {
                Button(action: model.goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)

                Spacer()

                Button(action: model.goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)

                Spacer()

                Button(action: model.openDashboard) {
                    Image(systemName: "house")
                }
                .accessibilityLabel("Open dashboard")

                Spacer()

                Button(action: model.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh dashboard")

                Spacer()

                Button(action: { showingShare = true }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear { model.start() }
        .sheet(isPresented: $showingShare) {
            ActivityView(activityItems: [model.shareURL])
        }
    }
}

final class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isOnline = true

    let webView: WKWebView
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "RememberPills.Network")
    private var started = false

    var shareURL: URL { webView.url ?? dashboardURL }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.alwaysBounceVertical = true
        webView.allowsLinkPreview = false
    }

    func start() {
        guard !started else { return }
        started = true

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: monitorQueue)

        // The app always starts at the user's dashboard, never the public homepage.
        webView.load(URLRequest(url: dashboardURL))
    }

    func openDashboard() {
        webView.load(URLRequest(url: dashboardURL))
    }

    func reload() { webView.reload() }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }

    private func updateNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame == nil,
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            if isRememberPillsURL(url) {
                webView.load(URLRequest(url: url))
            } else {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            if isRememberPillsURL(url) {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if isRememberPillsURL(url) {
            webView.load(URLRequest(url: url))
        } else {
            UIApplication.shared.open(url)
        }
        return nil
    }

    private func isRememberPillsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return rememberPillsHosts.contains(host)
    }
}

struct WebContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
