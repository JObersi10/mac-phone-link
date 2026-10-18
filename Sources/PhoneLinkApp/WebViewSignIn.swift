// WebViewSignIn — an in-app browser sign-in for a Microsoft Account, as an
// alternative to the Entra/MSAL flow.
//
// WHAT THIS DOES (and deliberately does NOT do):
//   • It opens a WKWebView to Microsoft's own sign-in page and lets the USER
//     authenticate themselves, with their own account, in a real browser view.
//   • When the user confirms they are signed in, it reads the MSA *session
//     cookies* that the login produced (the `login.live.com` / `*.microsoft.com`
//     auth cookies) from the web view's own cookie store, and returns them.
//   • It NEVER reads, captures, types, or stores the user's password. There is
//     no form scraping and no credential interception — only the token/cookie
//     that the user's own completed login hands back, exactly like any OAuth
//     web flow. The password stays between the user and Microsoft's page.
//
// Why cookies: the shipped client authenticates to DCG with a Microsoft Account
// *ticket* (MBI_SSL), not an Entra access token (see docs/FINDINGS.md § "DCG
// auth + device identity"). An authenticated MSA web session is what can later
// mint such a ticket. Turning these cookies into an MBI_SSL ticket (the RPS /
// PPCRL step) is NOT implemented here and is unverified — see the stub note in
// `MSAWebSession`.
//
// SPDX-License-Identifier: MIT

#if canImport(AppKit) && canImport(WebKit)
import Foundation
import AppKit
import WebKit

/// The result of an in-app Microsoft sign-in: a display label plus the MSA
/// session cookies the login produced. Never contains a password.
public struct MSAWebSession: Sendable {
    /// Best-effort account label (e.g. an email), or nil if not readable.
    public let accountLabel: String?
    /// The Microsoft auth cookies captured from the signed-in web session.
    public let cookies: [HTTPCookie]
    /// When the session was captured.
    public let capturedAt: Date

    public init(accountLabel: String?, cookies: [HTTPCookie], capturedAt: Date = Date()) {
        self.accountLabel = accountLabel
        self.cookies = cookies
        self.capturedAt = capturedAt
    }

    /// The most recently captured session, for the auth layer to consume.
    /// Process-lifetime only; not persisted to disk here.
    @MainActor public static var current: MSAWebSession?

    // NEXT STEP (not implemented, unverified): exchange these cookies for an
    // `MBI_SSL` ticket scoped to the DCG host via the MSA RPS/PPCRL endpoint,
    // then present it with `Authorization-Type: MSA`. That requires a live test
    // against Microsoft (docs/EVIDENCE_PLAN.md).
}

public enum WebViewSignInError: LocalizedError {
    case cancelled
    case noCookiesCaptured
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign-in was cancelled."
        case .noCookiesCaptured:
            return "No Microsoft session cookies were found. Make sure you completed sign-in before continuing."
        }
    }
}

@MainActor
public final class WebViewSignIn: NSObject {

    /// Microsoft Account sign-in landing. The user drives the whole flow here.
    public nonisolated static let defaultStartURL = URL(string: "https://login.live.com/")!

    /// Cookie domains we treat as the Microsoft auth session.
    private static let authCookieDomains = [
        "login.live.com", ".live.com",
        "login.microsoftonline.com", "login.microsoft.com",
        "account.microsoft.com", ".microsoft.com",
    ]

    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<MSAWebSession, Error>?

    public override init() { super.init() }

    /// Present the in-app browser and resolve once the user confirms they have
    /// signed in. The user authenticates themselves; we read only the resulting
    /// session cookies.
    public func present(startURL: URL = WebViewSignIn.defaultStartURL) async throws -> MSAWebSession {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.buildWindow(startURL: startURL)
        }
    }

    private func buildWindow(startURL: URL) {
        let config = WKWebViewConfiguration()
        // Use a non-persistent store so this login is isolated to this window
        // and leaves nothing behind on disk.
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: config)
        self.webView = web
        web.load(URLRequest(url: startURL))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 740),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "Sign in to Microsoft"
        win.isReleasedWhenClosed = false
        win.delegate = self

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 740))
        web.frame = NSRect(x: 0, y: 60, width: 520, height: 680)
        web.autoresizingMask = [.width, .height]

        let note = NSTextField(labelWithString: "Sign in with your own account. We never see your password — only the session it creates.")
        note.frame = NSRect(x: 16, y: 32, width: 488, height: 18)
        note.font = .systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor

        let doneButton = NSButton(title: "I'm signed in — continue", target: self, action: #selector(doneTapped))
        doneButton.frame = NSRect(x: 300, y: 8, width: 204, height: 24)
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.frame = NSRect(x: 16, y: 8, width: 90, height: 24)
        cancelButton.bezelStyle = .rounded

        container.addSubview(web)
        container.addSubview(note)
        container.addSubview(doneButton)
        container.addSubview(cancelButton)
        win.contentView = container
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    @objc private func doneTapped() {
        guard let web = webView else { return finish(.failure(WebViewSignInError.noCookiesCaptured)) }
        let store = web.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let auth = cookies.filter { cookie in
                Self.authCookieDomains.contains { cookie.domain == $0 || cookie.domain.hasSuffix($0) }
            }
            Task { @MainActor in
                guard !auth.isEmpty else {
                    self.finish(.failure(WebViewSignInError.noCookiesCaptured))
                    return
                }
                self.readAccountLabel { label in
                    let session = MSAWebSession(accountLabel: label, cookies: auth)
                    MSAWebSession.current = session
                    self.finish(.success(session))
                }
            }
        }
    }

    /// Best-effort, non-sensitive: try to read a visible account email from the
    /// page DOM. Never reads password fields. Returns nil on any failure.
    private func readAccountLabel(_ completion: @escaping @MainActor (String?) -> Void) {
        let js = "document.querySelector('[data-testid=\"userEmail\"]')?.textContent || "
            + "document.querySelector('.mectrl_name, .me-control, [aria-label*=\"account\"]')?.textContent || ''"
        webView?.evaluateJavaScript(js) { value, _ in
            Task { @MainActor in
                let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                completion((s?.isEmpty == false) ? s : nil)
            }
        }
    }

    @objc private func cancelTapped() { finish(.failure(WebViewSignInError.cancelled)) }

    private func finish(_ result: Result<MSAWebSession, Error>) {
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
        webView = nil
        guard let cont = continuation else { return }
        continuation = nil
        switch result {
        case .success(let s): cont.resume(returning: s)
        case .failure(let e): cont.resume(throwing: e)
        }
    }
}

extension WebViewSignIn: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        // Treat a window close as cancel if we haven't resolved yet.
        finish(.failure(WebViewSignInError.cancelled))
    }
}

public extension WebViewSignIn {
    /// Build the closure `OnboardingViewModel.signInAction` expects: run the
    /// in-app browser sign-in and return a display label. Needs no Entra client
    /// id — the user signs into their own account and we keep only the session.
    @MainActor
    static func makeSignInAction(startURL: URL = WebViewSignIn.defaultStartURL) -> () async throws -> String {
        return {
            let session = try await WebViewSignIn().present(startURL: startURL)
            return session.accountLabel ?? "Signed in (\(session.cookies.count) session cookies)"
        }
    }
}
#endif
