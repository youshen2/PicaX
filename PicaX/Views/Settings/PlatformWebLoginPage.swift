import SwiftUI
import WebKit

struct PlatformWebLoginPage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    let platform: ComicPlatform

    @State private var title = "网页登录"
    @State private var currentURL: URL?
    @State private var latestCookies = [HTTPCookie]()
    @State private var message: String?
    @State private var isSaving = false
    @State private var didSave = false

    private let service = ComicContentService()
    private let desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    var body: some View {
        Group {
            if let initialURL {
                LoginWebView(
                    initialURL: initialURL,
                    userAgent: desktopUserAgent,
                    onTitleChanged: { title = $0.isEmpty ? "网页登录" : $0 },
                    onCookiesChanged: { url, cookies in
                        currentURL = url
                        latestCookies = cookies
                        Task {
                            await saveIfReady(cookies: cookies, currentURL: url, automatic: true)
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
                        await saveIfReady(cookies: latestCookies, currentURL: currentURL ?? initialURL, automatic: false)
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("完成")
                    }
                }
                .disabled(isSaving || latestCookies.isEmpty)
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
    private func saveIfReady(cookies: [HTTPCookie], currentURL: URL?, automatic: Bool) async {
        guard !didSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let account = try await makeAccount(cookies: cookies, currentURL: currentURL, automatic: automatic)
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

    private func makeAccount(cookies: [HTTPCookie], currentURL: URL?, automatic: Bool) async throws -> PlatformAccount {
        let relevantCookies = cookies.filter { platform.acceptsWebLoginCookie($0) }
        let tokenCookie = relevantCookies.first { platform.tokenCookieNames.contains($0.name) }
        let refreshCookie = relevantCookies.first { platform.refreshTokenCookieNames.contains($0.name) }

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
                    userAgent: desktopUserAgent,
                    baseURL: PlatformFeatureSettings.frontendBaseURL(for: platform),
                    source: .web,
                    profile: PlatformAccountProfile(email: profile.email, username: profile.id, nickname: profile.name)
                )
            )
        case .nhentai:
            guard !relevantCookies.isEmpty,
                  tokenCookie != nil || relevantCookies.contains(where: { $0.name == "sessionid" }) || !automatic else {
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
                    userAgent: desktopUserAgent,
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
            return cookieBackedAccount(cookies: relevantCookies, currentURL: currentURL)
        case .jmComic, .htManga:
            guard !automatic, !relevantCookies.isEmpty else {
                throw PlatformWebLoginError.notReady
            }
            return cookieBackedAccount(cookies: relevantCookies, currentURL: currentURL)
        case .hitomi:
            guard !relevantCookies.isEmpty else {
                throw PlatformWebLoginError.notReady
            }
            return cookieBackedAccount(cookies: relevantCookies, currentURL: currentURL)
        }
    }

    private func cookieBackedAccount(cookies: [HTTPCookie], currentURL: URL?) -> PlatformAccount {
        PlatformAccount(
            platform: platform,
            username: platform.webLoginDisplayName(cookies: cookies, fallback: currentURL?.host),
            credential: PlatformCredential(
                token: cookies.first { platform.tokenCookieNames.contains($0.name) }?.value,
                refreshToken: cookies.first { platform.refreshTokenCookieNames.contains($0.name) }?.value,
                tokenType: nil,
                password: nil,
                cookies: cookies.map(StoredHTTPCookie.init(cookie:)),
                userAgent: desktopUserAgent,
                baseURL: PlatformFeatureSettings.frontendBaseURL(for: platform),
                source: .web,
                profile: PlatformAccountProfile(email: nil, username: nil, nickname: nil)
            )
        )
    }
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
    let userAgent: String
    let onTitleChanged: (String) -> Void
    let onCookiesChanged: (URL?, [HTTPCookie]) -> Void

    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.customUserAgent = userAgent
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateWebView(_ webView: WKWebView) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitleChanged: onTitleChanged, onCookiesChanged: onCookiesChanged)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onTitleChanged: (String) -> Void
        private let onCookiesChanged: (URL?, [HTTPCookie]) -> Void

        init(onTitleChanged: @escaping (String) -> Void, onCookiesChanged: @escaping (URL?, [HTTPCookie]) -> Void) {
            self.onTitleChanged = onTitleChanged
            self.onCookiesChanged = onCookiesChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onTitleChanged(webView.title ?? "")
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [onCookiesChanged] cookies in
                DispatchQueue.main.async {
                    onCookiesChanged(webView.url, cookies)
                }
            }
        }
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
