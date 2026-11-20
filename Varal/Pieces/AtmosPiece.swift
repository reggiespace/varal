import AppKit
import Network
import WebKit

/// Weak proxy breaking the `WKUserContentController.add(_:name:)` retain
/// cycle (the controller retains its script-message handlers).
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(target: any WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Live weather companion hosting `https://atmos.reggiespace.ca/?mode=piece`
/// in a `WKWebView`. The web app posts `EnvironmentSnapshot` JSON via
/// `window.webkit.messageHandlers.varalEnvironment.postMessage(...)`.
///
/// Varal holds no weather API key. If no telemetry arrives (offline, load
/// failure, disabled piece), `environmentalBroadcast` is nil and physics
/// uses the calm fallback breeze (6 km/h). The compact "?mode=piece" layout
/// and JS bridge inside the Atmos web app are an external dependency owned
/// by the Atmos repo — not a Varal deliverable.
@MainActor
public final class AtmosPiece: NSObject, CompanionPiece {
    public let pieceID = "atmos"
    public let displayName = "Atmos"
    public nonisolated var id: String { pieceID }
    public let sizeMetrics = PieceSizeMetrics(width: 170, height: 205, massUnits: 6.0)
    public let pinCount = 2
    public let preferredSide = PieceAnchorSide.leading

    public private(set) var environmentalBroadcast: EnvironmentSnapshot?

    private static let host = "atmos.reggiespace.ca"
    private static let pieceURL = URL(string: "https://atmos.reggiespace.ca/?mode=piece")!

    private let container = NSView()
    private var webView: WKWebView?
    private var lastGoodSnapshot: (snapshot: EnvironmentSnapshot, at: Date)?
    private var reloadAttempts = 0
    private var pathMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    private var suspended = false

    @MainActor public var pieceView: NSView { container }

    public override init() {
        super.init()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        buildWebView()
        observeReachability()
    }

    // MARK: - Web view lifecycle

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(
            WeakScriptMessageHandler(target: self),
            name: "varalEnvironment"
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.webView = webView
        webView.load(URLRequest(url: Self.pieceURL))
    }

    /// Occlusion governor hook: freeze the live web content behind a static
    /// snapshot so WebContent/GPU helpers drop to 0% CPU/GPU. Resume reloads.
    public func setSuspended(_ suspended: Bool) {
        guard suspended != self.suspended else { return }
        self.suspended = suspended
        if suspended {
            webView?.evaluateJavaScript("window.dispatchEvent(new Event('varal-pause'))", completionHandler: nil)
            webView?.isHidden = true
        } else {
            webView?.isHidden = false
            webView?.evaluateJavaScript("window.dispatchEvent(new Event('varal-resume'))", completionHandler: nil)
        }
    }

    private func scheduleReload() {
        reloadAttempts += 1
        let delay = min(60, pow(2.0, Double(min(reloadAttempts, 6))))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.webView?.load(URLRequest(url: Self.pieceURL)) }
        }
    }

    private func observeReachability() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.reloadIfNeverLoaded() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "ca.reggiespace.varal.atmos-path"))
        pathMonitor = monitor

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfNeverLoaded() }
        }
    }

    private func reloadIfNeverLoaded() {
        if environmentalBroadcast == nil, let webView = webView, webView.url == nil {
            webView.load(URLRequest(url: Self.pieceURL))
        }
    }

    private func noteSnapshot(_ snapshot: EnvironmentSnapshot) {
        environmentalBroadcast = snapshot
        lastGoodSnapshot = (snapshot, Date())
        reloadAttempts = 0
        // Expire the cached snapshot after 30 minutes without fresh telemetry.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30 * 60) { [weak self] in
            MainActor.assumeIsolated { self?.expireSnapshotIfStale() }
        }
    }

    private func expireSnapshotIfStale() {
        if let last = lastGoodSnapshot, Date().timeIntervalSince(last.at) >= 30 * 60 {
            lastGoodSnapshot = nil
            environmentalBroadcast = nil
        }
    }
}

// MARK: - WKScriptMessageHandler (origin-validated telemetry)

extension AtmosPiece: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "varalEnvironment" else { return }
        guard message.frameInfo.securityOrigin.host == Self.host else { return }
        let decoder = JSONDecoder()
        if let dict = message.body as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let snapshot = try? decoder.decode(EnvironmentSnapshot.self, from: data) {
            noteSnapshot(snapshot)
        }
    }
}

// MARK: - WKNavigationDelegate (same-origin lock + crash recovery)

extension AtmosPiece: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let host = navigationAction.request.url?.host, host == Self.host {
            decisionHandler(.allow)
        } else if navigationAction.request.url?.scheme == "about" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        scheduleReload()
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        scheduleReload()
    }
}
