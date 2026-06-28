import SwiftUI
import WebKit

struct PlatformWebLoginPage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    let platform: ComicPlatform

    @State private var title = "网页登录"
    @State private var currentURL: URL?
    @State private var latestCookies = [HTTPCookie]()
    @State private var latestUserAgent: String?
    @State private var webView: WKWebView?
    @State private var message: String?
    @State private var isSaving = false
    @State private var didSave = false

    private let service = ComicContentService()

    var body: some View {
        Group {
            if let initialURL {
                LoginWebView(
                    initialURL: initialURL,
                    userAgent: nil,
                    onWebViewReady: { webView = $0 },
                    onTitleChanged: { title = $0.isEmpty ? "网页登录" : $0 },
                    onCookiesChanged: { url, cookies, userAgent in
                        currentURL = url
                        latestCookies = cookies
                        latestUserAgent = userAgent
                        Task {
                            await saveIfReady(cookies: cookies, currentURL: url, userAgent: userAgent, automatic: true)
                        }
                    }
                )
            } else {
                ContentUnavailableView("无法打开网页登录", systemImage: "safari", description: Text("当前来源没有可用登录地址。"))
            }
        }
        .navigationTitle(title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        await saveFromCurrentWebView(automatic: false)
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("完成")
                    }
                }
                .disabled(isSaving || initialURL == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(message == "登录成功" ? .green : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }

    private var initialURL: URL? {
        platform.loginWebsite.flatMap(URL.init(string:))
    }

    @MainActor
    private func saveIfReady(cookies: [HTTPCookie], currentURL: URL?, userAgent: String?, automatic: Bool) async {
        guard !didSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let account = try await makeAccount(cookies: cookies, currentURL: currentURL, userAgent: userAgent, automatic: automatic)
            platformAccounts.saveValidatedAccount(account)
            didSave = true
            message = "登录成功"
            dismiss()
        } catch PlatformWebLoginError.notReady where automatic {
            message = platform.webLoginWaitingText
        } catch {
            if !automatic {
                message = error.localizedDescription
            }
        }
    }

    @MainActor
    private func saveFromCurrentWebView(automatic: Bool) async {
        let state = await currentWebLoginState()
        currentURL = state.url
        latestCookies = state.cookies
        latestUserAgent = state.userAgent
        await saveIfReady(cookies: state.cookies, currentURL: state.url, userAgent: state.userAgent, automatic: automatic)
    }

    @MainActor
    private func currentWebLoginState() async -> WebLoginState {
        guard let webView else {
            return WebLoginState(url: currentURL ?? initialURL, cookies: latestCookies, userAgent: latestUserAgent)
        }

        async let userAgent = webView.currentUserAgent()
        async let cookies = webView.allCookies()
        return WebLoginState(
            url: webView.url ?? currentURL ?? initialURL,
            cookies: await cookies,
            userAgent: await userAgent ?? latestUserAgent
        )
    }

    private func makeAccount(cookies: [HTTPCookie], currentURL: URL?, userAgent: String?, automatic: Bool) async throws -> PlatformAccount {
        let relevantCookies = cookies.filter { platform.acceptsWebLoginCookie($0) }
        let tokenCookie = relevantCookies.first { platform.tokenCookieNames.contains($0.name) }
        let refreshCookie = relevantCookies.first { platform.refreshTokenCookieNames.contains($0.name) }
        let accountUserAgent = PlatformWebUserAgent.normalized(userAgent)

        switch platform {
        case .picacg:
            guard let token = tokenCookie?.value, !token.isEmpty else {
                throw PlatformWebLoginError.notReady
            }
            let profile = try await service.loadPicacgProfile(token: token)
            return PlatformAccount(
                platform: platform,
                username: profile.email,
                credential: PlatformCredential(
                    token: token,
                    refreshToken: nil,
                    tokenType: nil,
                    password: nil,
                    cookies: relevantCookies.map(StoredHTTPCookie.init(cookie:)),
                    userAgent: accountUserAgent,
                    baseURL: PlatformFeatureSettings.frontendBaseURL(for: platform),
                    source: .web,
                    profile: PlatformAccountProfile(email: profile.email, username: profile.id, nickname: profile.name)
                )
            )
        case .nhentai:
            let hasTokenOrSessionCookie = tokenCookie != nil || relevantCookies.contains { $0.name == "sessionid" }
            let hasXSRFCookieAfterLoginPage = relevantCookies.contains { $0.name == "XSRF-TOKEN" } && currentURL?.isLikelyLoginPage != true
            guard !relevantCookies.isEmpty,
                  hasTokenOrSessionCookie || (!automatic && !relevantCookies.isEmpty) || hasXSRFCookieAfterLoginPage else {
                throw PlatformWebLoginError.notReady
            }
            return PlatformAccount(
                platform: platform,
                username: platform.webLoginDisplayName(cookies: relevantCookies, fallback: currentURL?.host),
                credential: PlatformCredential(
                    token: tokenCookie?.value,
                    refreshToken: refreshCookie?.value,
                    tokenType: tokenCookie == nil ? nil : "User",
                    password: nil,
                    cookies: relevantCookies.map(StoredHTTPCookie.init(cookie:)),
                    userAgent: accountUserAgent,
                    baseURL: PlatformFeatureSettings.frontendBaseURL(for: platform),
                    source: .web,
                    profile: PlatformAccountProfile(email: nil, username: nil, nickname: nil)
                )
            )
        case .eHentai:
            let names = Set(relevantCookies.map(\.name))
            let hasLoginCookie = names.contains("ipb_member_id") && names.contains("ipb_pass_hash")
            guard hasLoginCookie || (!automatic && !relevantCookies.isEmpty) else {
                throw PlatformWebLoginError.notReady
            }
            return cookieBackedAccount(cookies: relevantCookies, currentURL: currentURL, userAgent: accountUserAgent)
        case .jmComic:
            guard !automatic, !relevantCookies.isEmpty else {
                throw PlatformWebLoginError.notReady
            }
            return cookieBackedAccount(cookies: relevantCookies, currentURL: currentURL, userAgent: accountUserAgent)
        case .htManga:
            guard !relevantCookies.isEmpty, !automatic || currentURL?.isLikelyLoginPage != true else {
                throw PlatformWebLoginError.notReady
            }
            return cookieBackedAccount(cookies: relevantCookies, currentURL: currentURL, userAgent: accountUserAgent)
        case .hitomi:
            guard !relevantCookies.isEmpty else {
                throw PlatformWebLoginError.notReady
            }
            return cookieBackedAccount(cookies: relevantCookies, currentURL: currentURL, userAgent: accountUserAgent)
        }
    }

    private func cookieBackedAccount(cookies: [HTTPCookie], currentURL: URL?, userAgent: String) -> PlatformAccount {
        PlatformAccount(
            platform: platform,
            username: platform.webLoginDisplayName(cookies: cookies, fallback: currentURL?.host),
            credential: PlatformCredential(
                token: cookies.first { platform.tokenCookieNames.contains($0.name) }?.value,
                refreshToken: cookies.first { platform.refreshTokenCookieNames.contains($0.name) }?.value,
                tokenType: nil,
                password: nil,
                cookies: cookies.map(StoredHTTPCookie.init(cookie:)),
                userAgent: userAgent,
                baseURL: PlatformFeatureSettings.frontendBaseURL(for: platform),
                source: .web,
                profile: PlatformAccountProfile(email: nil, username: nil, nickname: nil)
            )
        )
    }
}

private struct WebLoginState {
    var url: URL?
    var cookies: [HTTPCookie]
    var userAgent: String?
}

private enum PlatformWebLoginError: LocalizedError {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady:
            "还没有检测到可保存的登录状态"
        }
    }
}

private extension ComicPlatform {
    var webLoginWaitingText: String {
        switch self {
        case .picacg:
            "请在网页中完成登录。"
        case .nhentai:
            "请在网页中完成登录。"
        case .eHentai:
            "请在网页中完成登录。"
        case .jmComic, .htManga, .hitomi:
            "登录完成后点“完成”保存。"
        }
    }

    var tokenCookieNames: Set<String> {
        switch self {
        case .picacg:
            ["token", "access_token"]
        case .nhentai:
            ["access_token"]
        default:
            []
        }
    }

    var refreshTokenCookieNames: Set<String> {
        switch self {
        case .nhentai:
            ["refresh_token"]
        default:
            []
        }
    }

    func acceptsWebLoginCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return webLoginDomains.contains { accepted in
            domain == accepted || domain.hasSuffix(".\(accepted)")
        }
    }

    var webLoginDomains: [String] {
        var hosts = [String]()
        if let host = URL(string: PlatformFeatureSettings.frontendBaseURL(for: self))?.host {
            hosts.append(host.lowercased())
        }
        switch self {
        case .picacg:
            hosts.append("picacomic.com")
        case .nhentai:
            hosts.append("nhentai.net")
        case .eHentai:
            hosts.append(contentsOf: ["e-hentai.org", "exhentai.org"])
        case .jmComic:
            hosts.append(contentsOf: ["18comic.vip", "jmcomic1.me"])
        case .hitomi:
            hosts.append("hitomi.la")
        case .htManga:
            hosts.append(contentsOf: ["wnacg.com", "www.wnacg.com"])
        }
        return Array(Set(hosts))
    }

    func webLoginDisplayName(cookies: [HTTPCookie], fallback: String?) -> String {
        if let token = cookies.first(where: { tokenCookieNames.contains($0.name) })?.value, !token.isEmpty {
            return title
        }
        if let memberID = cookies.first(where: { $0.name == "ipb_member_id" })?.value, !memberID.isEmpty {
            return memberID
        }
        return fallback ?? title
    }
}

private struct LoginWebView {
    let initialURL: URL
    let userAgent: String?
    let onWebViewReady: (WKWebView) -> Void
    let onTitleChanged: (String) -> Void
    let onCookiesChanged: (URL?, [HTTPCookie], String?) -> Void

    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        if let userAgent {
            webView.customUserAgent = userAgent
        }
        coordinator.attach(webView)
        DispatchQueue.main.async {
            onWebViewReady(webView)
        }
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateWebView(_ webView: WKWebView) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitleChanged: onTitleChanged, onCookiesChanged: onCookiesChanged)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let onTitleChanged: (String) -> Void
        private let onCookiesChanged: (URL?, [HTTPCookie], String?) -> Void
        private weak var webView: WKWebView?
        private weak var cookieStore: WKHTTPCookieStore?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?

        init(onTitleChanged: @escaping (String) -> Void, onCookiesChanged: @escaping (URL?, [HTTPCookie], String?) -> Void) {
            self.onTitleChanged = onTitleChanged
            self.onCookiesChanged = onCookiesChanged
        }

        deinit {
            cookieStore?.remove(self)
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            self.cookieStore = cookieStore
            cookieStore.add(self)

            titleObservation = webView.observe(\.title, options: [.new]) { [weak self, weak webView] observedWebView, _ in
                self?.onTitleChanged(observedWebView.title ?? "")
                if let currentWebView = webView {
                    self?.collectState(from: currentWebView)
                }
            }
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self, weak webView] _, _ in
                if let webView {
                    self?.collectState(from: webView)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onTitleChanged(webView.title ?? "")
            collectState(from: webView)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard let webView else { return }
            collectState(from: webView)
        }

        private func collectState(from webView: WKWebView) {
            webView.evaluateJavaScript("navigator.userAgent") { [weak webView, onCookiesChanged] result, _ in
                let trimmedUserAgent = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let userAgent = trimmedUserAgent.isEmpty ? nil : trimmedUserAgent
                guard let webView else { return }
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    DispatchQueue.main.async {
                        onCookiesChanged(webView.url, cookies, userAgent)
                    }
                }
            }
        }
    }
}

private extension WKWebView {
    @MainActor
    func currentUserAgent() async -> String? {
        await withCheckedContinuation { continuation in
            evaluateJavaScript("navigator.userAgent") { result, _ in
                let trimmed = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: trimmed.isEmpty ? nil : trimmed)
            }
        }
    }

    @MainActor
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

private extension URL {
    var isLikelyLoginPage: Bool {
        let lowercasedPath = path.lowercased()
        return lowercasedPath.contains("login") || lowercasedPath.contains("register")
    }
}

#if os(macOS)
extension LoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        updateWebView(nsView)
    }
}
#else
extension LoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        updateWebView(uiView)
    }
}
#endif
