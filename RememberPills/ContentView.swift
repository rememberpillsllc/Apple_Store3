import SwiftUI
import WebKit
import Network
import UIKit
import StoreKit

private let dashboardURL = URL(string: "https://www.rememberpills.com/app-login.php")!
private let rememberPillsHosts: Set<String> = ["www.rememberpills.com", "rememberpills.com"]
private let monthlyProductID = "com.rememberpills.app.monthly"

// MARK: - Store Manager

@MainActor
final class StoreManager: ObservableObject {
    @Published var isPurchased = false
    @Published var product: Product?
    @Published var isLoading = true
    @Published var purchaseError: String?

    private var updateTask: Task<Void, Never>?

    init() {
        updateTask = Task {
            await listenForTransactions()
        }
        Task {
            await loadProduct()
            await checkEntitlement()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [monthlyProductID])
            self.product = products.first
        } catch {
            purchaseError = "Could not load subscription info."
        }
        isLoading = false
    }

    func purchase() async {
        guard let product = product else { return }
        isLoading = true
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    isPurchased = true
                case .unverified:
                    purchaseError = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
        isLoading = false
    }

    func restore() async {
        isLoading = true
        try? await AppStore.sync()
        await checkEntitlement()
        isLoading = false
    }

    func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == monthlyProductID,
               transaction.revocationDate == nil {
                isPurchased = true
                return
            }
        }
        isPurchased = false
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == monthlyProductID {
                    await transaction.finish()
                    await checkEntitlement()
                }
            }
        }
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @ObservedObject var store: StoreManager

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.49, blue: 0.49)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo / icon area
                Image(systemName: "pills.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white)
                    .padding(.bottom, 16)

                Text("RememberPills.com")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text("Medication Reminders for the Family")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 4)

                Spacer().frame(height: 36)

                // Feature bullets
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "bell.fill",    text: "Daily automated pill reminders by text")
                    FeatureRow(icon: "person.2.fill", text: "MyPillCircle™ caregiver notifications")
                    FeatureRow(icon: "checkmark.circle.fill", text: "Works on any phone — no app required")
                    FeatureRow(icon: "lock.open.fill", text: "No password needed")
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                // Price
                if let product = store.product {
                    Text(product.displayPrice + " / month")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("Cancel anytime")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.top, 2)
                }

                Spacer().frame(height: 24)

                // Subscribe button
                Button(action: {
                    Task { await store.purchase() }
                }) {
                    if store.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.04, green: 0.49, blue: 0.49)))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white)
                            .cornerRadius(14)
                    } else {
                        Text("Start Free 30-Day Trial")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 0.04, green: 0.49, blue: 0.49))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white)
                            .cornerRadius(14)
                    }
                }
                .disabled(store.isLoading || store.product == nil)
                .padding(.horizontal, 28)

                // Error message
                if let error = store.purchaseError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                }

                // Restore purchases
                Button(action: {
                    Task { await store.restore() }
                }) {
                    Text("Restore Purchase")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .underline()
                }
                .padding(.top, 16)

                Spacer().frame(height: 12)

                // Legal
                Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Manage or cancel in App Store Settings.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var store = StoreManager()
    @StateObject private var model = WebViewModel()
    @State private var showingShare = false

    var body: some View {
        Group {
            if store.isLoading && !store.isPurchased {
                // Brief loading screen while checking entitlement
                ZStack {
                    Color(red: 0.04, green: 0.49, blue: 0.49).ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            } else if store.isPurchased {
                // Subscribed — show the full app
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
            } else {
                // Not subscribed — show paywall
                PaywallView(store: store)
            }
        }
        .onChange(of: store.isPurchased) { purchased in
            if purchased { model.start() }
        }
    }
}

// MARK: - Web View Model

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

// MARK: - Supporting Views

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
