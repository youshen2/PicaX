import Foundation
import SwiftUI

struct HomeComicSourceRow: View {
    let platform: ComicPlatform
    let account: PlatformAccount?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(platform.title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: platform.systemImage)
                .foregroundStyle(platform.accentColor)
        }
    }

    private var subtitle: String {
        if let account {
            return account.displayName
        }
        switch platform {
        case .picacg:
            return "分流、头像框、打卡、我的评论"
        case .jmComic:
            return "API、图片分流、签到"
        case .nhentai:
            return "前端与网页登录"
        case .eHentai:
            return "站点、原图、警告、Profile"
        case .hitomi:
            return "前端与图片数据域名"
        case .htManga:
            return "API 分流"
        }
    }
}

struct HomeComicSourceFeaturePage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    let platform: ComicPlatform
    let service: ComicContentService

    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.picacg)) private var picacgFrontendURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .picacg)
    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.jmComic)) private var jmFrontendURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .jmComic)
    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.nhentai)) private var nhentaiFrontendURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .nhentai)
    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.eHentai)) private var ehentaiFrontendURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .eHentai)
    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.hitomi)) private var hitomiFrontendURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .hitomi)
    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.htManga)) private var htMangaFrontendURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .htManga)

    @State private var message: SourceFeatureMessage?

    var body: some View {
        List {
            accountSection
            frontendSection

            switch platform {
            case .picacg:
                PicacgSourceFeatureSection(service: service, account: account, showMessage: showMessage)
            case .jmComic:
                JmComicSourceFeatureSection(service: service, account: account, showMessage: showMessage)
            case .nhentai:
                NhentaiSourceFeatureSection(showMessage: showMessage)
            case .eHentai:
                EhentaiSourceFeatureSection(service: service, showMessage: showMessage)
            case .hitomi:
                HitomiSourceFeatureSection(showMessage: showMessage)
            case .htManga:
                HtMangaSourceFeatureSection(service: service, showMessage: showMessage)
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle(platform.title)
        .picaxHidesTabBar()
        .alert(item: $message) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("好"))
            )
        }
        .onDisappear {
            normalizeFrontendURL()
        }
    }

    private var account: PlatformAccount? {
        platformAccounts.account(for: platform)
    }

    private var accountSection: some View {
        Section("账号") {
            NavigationLink {
                PlatformLoginView(platform: platform)
                    .picaxHidesTabBar()
            } label: {
                HomeComicSourceRow(platform: platform, account: account)
            }
        }
    }

    private var frontendSection: some View {
        Section {
            urlField("前端地址", text: frontendBinding, placeholder: PlatformFeatureSettings.defaultFrontendBaseURL(for: platform))

            if let url = URL(string: PlatformFeatureSettings.frontendBaseURL(for: platform)) {
                Link(destination: url) {
                    Label("打开前端", systemImage: "safari")
                }
            }

            Button("恢复默认前端") {
                frontendBinding.wrappedValue = PlatformFeatureSettings.defaultFrontendBaseURL(for: platform)
            }
        } header: {
            Text("前端")
        } footer: {
            Text("用于网页登录、分享链接，以及支持网页解析的来源请求。")
        }
    }

    private var frontendBinding: Binding<String> {
        switch platform {
        case .picacg:
            Binding(get: { picacgFrontendURL }, set: { picacgFrontendURL = $0 })
        case .jmComic:
            Binding(get: { jmFrontendURL }, set: { jmFrontendURL = $0 })
        case .nhentai:
            Binding(get: { nhentaiFrontendURL }, set: { nhentaiFrontendURL = $0 })
        case .eHentai:
            Binding(get: { ehentaiFrontendURL }, set: { ehentaiFrontendURL = $0 })
        case .hitomi:
            Binding(get: { hitomiFrontendURL }, set: { hitomiFrontendURL = $0 })
        case .htManga:
            Binding(get: { htMangaFrontendURL }, set: { htMangaFrontendURL = $0 })
        }
    }

    @ViewBuilder
    private func urlField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        LabeledContent {
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .picaxDisablesTextAutocapitalization()
                .autocorrectionDisabled()
                .picaxKeyboardType(.url)
        } label: {
            Text(title)
        }
    }

    private func normalizeFrontendURL() {
        frontendBinding.wrappedValue = PlatformFeatureSettings.normalizedBaseURL(
            frontendBinding.wrappedValue,
            fallback: PlatformFeatureSettings.defaultFrontendBaseURL(for: platform)
        )
    }

    private func showMessage(_ title: String, _ detail: String) {
        message = SourceFeatureMessage(title: title, detail: detail)
    }
}

private struct SourceFeatureMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private struct SourceRouteSpeedOption: Identifiable {
    let id: String
    let title: String
}

private struct SourceRouteSpeedTestControl: View {
    let actionTitle: String
    let options: [SourceRouteSpeedOption]
    let results: [SourceRouteSpeedTestResult]
    let selectedID: String?
    let isTesting: Bool
    let test: () -> Void
    let select: (String) -> Void

    var body: some View {
        Button(action: test) {
            if isTesting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在测速")
                }
            } else {
                Label(actionTitle, systemImage: "speedometer")
            }
        }
        .disabled(isTesting)

        if !results.isEmpty {
            ForEach(options) { option in
                if let result = results.first(where: { $0.id == option.id }) {
                    Button {
                        select(option.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                if !result.endpoint.isEmpty {
                                    Text(result.endpoint)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            HStack(spacing: 6) {
                                if result.id == fastestResultID {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("推荐")
                                }
                                Text(result.statusText)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(result.milliseconds == nil ? .red : .secondary)
                                if result.id == selectedID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(result.milliseconds == nil)
                }
            }

            Text("使用真实 HTTP 请求测量（非 Ping），数值越低通常越快；结果会受当前网络波动影响。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fastestResultID: String? {
        results
            .filter { $0.milliseconds != nil }
            .min { ($0.milliseconds ?? .max) < ($1.milliseconds ?? .max) }?
            .id
    }
}

private struct PicacgSourceFeatureSection: View {
    let service: ComicContentService
    let account: PlatformAccount?
    let showMessage: (String, String) -> Void

    @AppStorage(PlatformFeatureSettingsKey.picacgAppChannel) private var appChannel = "3"
    @AppStorage("settings.network.imageQuality") private var imageQuality = "均衡"
    @AppStorage(PlatformFeatureSettingsKey.picacgDefaultSort) private var defaultSort = PicacgSortMode.newest.rawValue
    @AppStorage(PlatformFeatureSettingsKey.picacgFavoriteSort) private var favoriteSort = PicacgFavoriteSort.oldest.rawValue
    @AppStorage(PlatformFeatureSettingsKey.picacgShowsAvatarFrame) private var showsAvatarFrame = true
    @AppStorage(PlatformFeatureSettingsKey.picacgAutoPunchIn) private var autoPunchIn = false

    @State private var isPunching = false
    @State private var isTestingAPIChannels = false
    @State private var apiChannelSpeedResults = [SourceRouteSpeedTestResult]()

    var body: some View {
        PicacgProfileSection(service: service, account: account)

        Section("PicACG") {
            Picker("分流", selection: $appChannel) {
                Text("分流 1").tag("1")
                Text("分流 2").tag("2")
                Text("分流 3").tag("3")
            }

            SourceRouteSpeedTestControl(
                actionTitle: "测试 API 分流",
                options: [
                    SourceRouteSpeedOption(id: "1", title: "分流 1"),
                    SourceRouteSpeedOption(id: "2", title: "分流 2"),
                    SourceRouteSpeedOption(id: "3", title: "分流 3")
                ],
                results: apiChannelSpeedResults,
                selectedID: appChannel,
                isTesting: isTestingAPIChannels,
                test: {
                    Task { await testAPIChannels() }
                },
                select: { appChannel = $0 }
            )

            Picker("图片质量", selection: $imageQuality) {
                Text("省流").tag("省流")
                Text("均衡").tag("均衡")
                Text("高清").tag("高清")
                Text("原图").tag("原图")
            }

            Picker("搜索与分类排序", selection: $defaultSort) {
                ForEach(PicacgSortMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Picker("收藏排序", selection: $favoriteSort) {
                ForEach(PicacgFavoriteSort.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Toggle("显示头像框", isOn: $showsAvatarFrame)
            Toggle("自动打卡", isOn: $autoPunchIn)

            Button {
                Task {
                    await punchIn()
                }
            } label: {
                if isPunching {
                    HStack {
                        ProgressView()
                        Text("正在打卡")
                    }
                } else {
                    Label("立即打卡", systemImage: "calendar.badge.checkmark")
                }
            }
            .disabled(isPunching || account == nil)

            NavigationLink {
                PicacgUserCommentsPage(service: service, account: account)
                    .picaxHidesTabBar()
            } label: {
                Label("我的评论", systemImage: "text.bubble")
            }
            .disabled(account == nil)
        }
    }

    @MainActor
    private func testAPIChannels() async {
        guard !isTestingAPIChannels else { return }
        isTestingAPIChannels = true
        defer { isTestingAPIChannels = false }
        do {
            apiChannelSpeedResults = try await service.testPicacgAPIChannels(account: account)
        } catch {
            showMessage("测速失败", error.localizedDescription)
        }
    }

    @MainActor
    private func punchIn() async {
        guard !isPunching else { return }
        isPunching = true
        defer { isPunching = false }
        do {
            try await service.picacgPunchIn(account: account)
            showMessage("打卡成功", "PicACG 已完成打卡。")
        } catch {
            showMessage("打卡失败", error.localizedDescription)
        }
    }
}

private struct PicacgProfileSection: View {
    let service: ComicContentService
    let account: PlatformAccount?

    @AppStorage(PlatformFeatureSettingsKey.picacgShowsAvatarFrame) private var showsAvatarFrame = true
    @State private var profile: PicacgUserProfile?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Section("资料") {
            if let profile {
                HStack(spacing: 12) {
                    ZStack {
                        CachedRemoteImageView(url: profile.avatarURL, accentColor: .pink, contentMode: .fill, maxPixelSize: 128)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        if showsAvatarFrame, let frameURL = profile.frameURL {
                            CachedRemoteImageView(url: frameURL, accentColor: .pink, contentMode: .fit, maxPixelSize: 160)
                                .frame(width: 62, height: 62)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.headline)
                        Text(profile.levelText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let slogan = profile.slogan, !slogan.isEmpty {
                            Text(slogan)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else if isLoading {
                HStack {
                    ProgressView()
                    Text("正在加载资料")
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                Text(account == nil ? "登录后显示 PicACG 资料。" : "尚未加载资料。")
                    .foregroundStyle(.secondary)
            }

            Button("刷新资料") {
                Task {
                    await loadProfile()
                }
            }
            .disabled(account == nil || isLoading)
        }
        .task(id: account?.id) {
            guard account != nil, profile == nil else { return }
            await loadProfile()
        }
    }

    @MainActor
    private func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            profile = try await service.loadPicacgProfile(account: account)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct JmComicSourceFeatureSection: View {
    let service: ComicContentService
    let account: PlatformAccount?
    let showMessage: (String, String) -> Void

    @AppStorage(PlatformFeatureSettingsKey.jmAutoSelectAPIEndpoint) private var autoSelectAPIEndpoint = true
    @AppStorage(PlatformFeatureSettingsKey.jmAPIEndpoint) private var apiEndpoint = JmAPIEndpoint.auto.rawValue
    @AppStorage(PlatformFeatureSettingsKey.jmCustomAPIBaseURLs) private var customAPIBaseURLs = ""
    @AppStorage(PlatformFeatureSettingsKey.jmImageEndpoint) private var imageEndpoint = JmImageEndpoint.mspProxy3.rawValue
    @AppStorage(PlatformFeatureSettingsKey.jmCustomImageBaseURL) private var customImageBaseURL = JmImageEndpoint.defaultBaseURL
    @AppStorage(PlatformFeatureSettingsKey.jmAppVersion) private var appVersion = "2.0.26"
    @AppStorage(PlatformFeatureSettingsKey.jmFavoriteSort) private var favoriteSort = JmFavoriteSort.latest.rawValue
    @AppStorage(PlatformFeatureSettingsKey.jmAutoCheckIn) private var autoCheckIn = false

    @State private var isUpdatingDomains = false
    @State private var isUpdatingVersion = false
    @State private var isCheckingIn = false
    @State private var isTestingAPIEndpoints = false
    @State private var isTestingImageEndpoints = false
    @State private var apiSpeedResults = [SourceRouteSpeedTestResult]()
    @State private var imageSpeedResults = [SourceRouteSpeedTestResult]()

    var body: some View {
        Section {
            Toggle("自动选择域名", isOn: $autoSelectAPIEndpoint)

            Picker("API 域名", selection: $apiEndpoint) {
                ForEach(JmAPIEndpoint.allCases) { endpoint in
                    Text(endpoint.title).tag(endpoint.rawValue)
                }
            }
            .disabled(autoSelectAPIEndpoint)

            if !customAPIBaseURLs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(customAPIBaseURLs)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await updateDomains()
                }
            } label: {
                if isUpdatingDomains {
                    HStack {
                        ProgressView()
                        Text("正在更新")
                    }
                } else {
                    Label("更新 API 域名", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isUpdatingDomains)

            SourceRouteSpeedTestControl(
                actionTitle: "测试 API 域名",
                options: jmAPIOptions,
                results: apiSpeedResults,
                selectedID: autoSelectAPIEndpoint ? nil : apiEndpoint,
                isTesting: isTestingAPIEndpoints,
                test: {
                    Task { await testAPIEndpoints() }
                },
                select: { id in
                    autoSelectAPIEndpoint = false
                    apiEndpoint = id
                }
            )

            Picker("图片分流", selection: $imageEndpoint) {
                ForEach(JmImageEndpoint.allCases) { endpoint in
                    Text(endpoint.title).tag(endpoint.rawValue)
                }
            }

            if selectedImageEndpoint == .custom {
                urlField("图片地址", text: $customImageBaseURL, placeholder: JmImageEndpoint.defaultBaseURL)
            }

            SourceRouteSpeedTestControl(
                actionTitle: "测试图片分流",
                options: jmImageOptions,
                results: imageSpeedResults,
                selectedID: imageEndpoint,
                isTesting: isTestingImageEndpoints,
                test: {
                    Task { await testImageEndpoints() }
                },
                select: { imageEndpoint = $0 }
            )

            Picker("收藏排序", selection: $favoriteSort) {
                ForEach(JmFavoriteSort.allCases) { sort in
                    Text(sort.title).tag(sort.rawValue)
                }
            }

            LabeledContent {
                TextField("2.0.26", text: $appVersion)
                    .multilineTextAlignment(.trailing)
                    .picaxDisablesTextAutocapitalization()
                    .autocorrectionDisabled()
            } label: {
                Text("App 版本")
            }

            Button {
                Task {
                    await updateVersion()
                }
            } label: {
                if isUpdatingVersion {
                    HStack {
                        ProgressView()
                        Text("正在更新")
                    }
                } else {
                    Label("更新 App 版本", systemImage: "arrow.down.doc")
                }
            }
            .disabled(isUpdatingVersion)
        } header: {
            Text("JMComic")
        } footer: {
            Text("API 域名影响登录和漫画数据，图片分流影响封面、头像和章节图片。")
        }

        Section("签到") {
            Toggle("每日自动签到", isOn: $autoCheckIn)

            Button {
                Task {
                    await checkIn()
                }
            } label: {
                if isCheckingIn {
                    HStack {
                        ProgressView()
                        Text("正在签到")
                    }
                } else {
                    Label("立即签到", systemImage: "calendar.badge.checkmark")
                }
            }
            .disabled(isCheckingIn || account == nil)
        }
    }

    private var selectedImageEndpoint: JmImageEndpoint {
        JmImageEndpoint(rawValue: imageEndpoint) ?? .mspProxy3
    }

    private var jmAPIOptions: [SourceRouteSpeedOption] {
        JmAPIEndpoint.allCases
            .filter { $0 != .auto }
            .map { SourceRouteSpeedOption(id: $0.id, title: $0.title) }
    }

    private var jmImageOptions: [SourceRouteSpeedOption] {
        JmImageEndpoint.allCases.map { SourceRouteSpeedOption(id: $0.id, title: $0.title) }
    }

    @ViewBuilder
    private func urlField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        LabeledContent {
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .picaxDisablesTextAutocapitalization()
                .autocorrectionDisabled()
                .picaxKeyboardType(.url)
        } label: {
            Text(title)
        }
    }

    @MainActor
    private func testAPIEndpoints() async {
        guard !isTestingAPIEndpoints else { return }
        isTestingAPIEndpoints = true
        defer { isTestingAPIEndpoints = false }
        apiSpeedResults = await service.testJmAPIEndpoints()
    }

    @MainActor
    private func testImageEndpoints() async {
        guard !isTestingImageEndpoints else { return }
        isTestingImageEndpoints = true
        defer { isTestingImageEndpoints = false }
        imageSpeedResults = await service.testJmImageEndpoints(customBaseURL: customImageBaseURL)
    }

    @MainActor
    private func updateDomains() async {
        guard !isUpdatingDomains else { return }
        isUpdatingDomains = true
        defer { isUpdatingDomains = false }
        do {
            let result = try await service.refreshJmAPIEndpoints()
            var detail = result.domainsText
            if let appVersion = result.appVersion {
                detail += "\nApp 版本：\(appVersion)"
            }
            showMessage("更新成功", detail)
        } catch {
            showMessage("更新失败", error.localizedDescription)
        }
    }

    @MainActor
    private func updateVersion() async {
        guard !isUpdatingVersion else { return }
        isUpdatingVersion = true
        defer { isUpdatingVersion = false }
        do {
            let version = try await service.refreshJmAppVersion()
            showMessage("更新成功", "App 版本：\(version)")
        } catch {
            showMessage("更新失败", error.localizedDescription)
        }
    }

    @MainActor
    private func checkIn() async {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        defer { isCheckingIn = false }
        do {
            let result = try await service.jmComicCheckIn(account: account)
            showMessage("签到完成", result)
        } catch {
            showMessage("签到失败", error.localizedDescription)
        }
    }
}

private struct NhentaiSourceFeatureSection: View {
    let showMessage: (String, String) -> Void

    var body: some View {
        Section("NHentai") {
            Button {
                SourceCookieCleaner.clear(hosts: ["nhentai.net", ".nhentai.net"])
                showMessage("已清除", "NHentai 的网页登录状态已清除。")
            } label: {
                Label("清除网页登录状态", systemImage: "trash")
            }
        }
    }
}

private struct EhentaiSourceFeatureSection: View {
    let service: ComicContentService
    let showMessage: (String, String) -> Void

    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.eHentai)) private var frontendURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .eHentai)
    @AppStorage(PlatformFeatureSettingsKey.ehentaiPrefersOriginalImage) private var prefersOriginalImage = false
    @AppStorage(PlatformFeatureSettingsKey.ehentaiIgnoresContentWarning) private var ignoresContentWarning = true
    @AppStorage(PlatformFeatureSettingsKey.ehentaiPrefersJapaneseTitle) private var prefersJapaneseTitle = false
    @State private var isTestingSites = false
    @State private var siteSpeedResults = [SourceRouteSpeedTestResult]()

    var body: some View {
        Section("E-Hentai") {
            Picker("画廊站点", selection: siteBinding) {
                ForEach(EhentaiSite.allCases) { site in
                    Text(site.title).tag(site.rawValue)
                }
            }

            SourceRouteSpeedTestControl(
                actionTitle: "测试画廊站点",
                options: EhentaiSite.allCases.map { SourceRouteSpeedOption(id: $0.id, title: $0.title) },
                results: siteSpeedResults,
                selectedID: selectedSiteID,
                isTesting: isTestingSites,
                test: {
                    Task { await testSites() }
                },
                select: { frontendURL = $0 }
            )

            Toggle("优先加载原图", isOn: $prefersOriginalImage)
            Toggle("忽略警告", isOn: $ignoresContentWarning)
            Toggle("优先显示副标题", isOn: $prefersJapaneseTitle)

            NavigationLink {
                EhentaiProfileSelectionPage(service: service)
                    .picaxHidesTabBar()
            } label: {
                Label("Profile", systemImage: "person.crop.square")
            }

            Button {
                SourceCookieCleaner.clear(hosts: ["e-hentai.org", ".e-hentai.org", "exhentai.org", ".exhentai.org"])
                showMessage("已清除", "E-Hentai 的网页登录状态已清除。")
            } label: {
                Label("清除网页登录状态", systemImage: "trash")
            }
        }
    }

    private var siteBinding: Binding<String> {
        Binding {
            EhentaiSite(rawValue: PlatformFeatureSettings.normalizedBaseURL(frontendURL, fallback: EhentaiSite.eHentai.rawValue))?.rawValue ?? EhentaiSite.eHentai.rawValue
        } set: { value in
            frontendURL = value
        }
    }

    private var selectedSiteID: String {
        EhentaiSite(rawValue: PlatformFeatureSettings.normalizedBaseURL(
            frontendURL,
            fallback: EhentaiSite.eHentai.rawValue
        ))?.id ?? EhentaiSite.eHentai.id
    }

    @MainActor
    private func testSites() async {
        guard !isTestingSites else { return }
        isTestingSites = true
        defer { isTestingSites = false }
        siteSpeedResults = await service.testEhentaiSites()
    }
}

private struct HitomiSourceFeatureSection: View {
    let showMessage: (String, String) -> Void

    @AppStorage(PlatformFeatureSettingsKey.hitomiDataDomain) private var dataDomain = "gold-usergeneratedcontent.net"

    var body: some View {
        Section {
            LabeledContent {
                TextField("gold-usergeneratedcontent.net", text: $dataDomain)
                    .multilineTextAlignment(.trailing)
                    .picaxDisablesTextAutocapitalization()
                    .autocorrectionDisabled()
                    .picaxKeyboardType(.url)
                    .onSubmit {
                        normalize()
                    }
            } label: {
                Text("图片数据域名")
            }

            Button("恢复默认域名") {
                dataDomain = "gold-usergeneratedcontent.net"
                showMessage("已恢复", "Hitomi 图片数据域名已恢复默认。")
            }
        } header: {
            Text("Hitomi")
        } footer: {
            Text("用于缩略图、索引和原图资源。只填写域名即可。")
        }
        .onDisappear {
            normalize()
        }
    }

    private func normalize() {
        dataDomain = PlatformFeatureSettings.normalizedDomain(dataDomain, fallback: "gold-usergeneratedcontent.net")
    }
}

private struct HtMangaSourceFeatureSection: View {
    let service: ComicContentService
    let showMessage: (String, String) -> Void

    @AppStorage(PlatformFeatureSettingsKey.frontendBaseURL(.htManga)) private var apiBaseURL = PlatformFeatureSettings.defaultFrontendBaseURL(for: .htManga)
    @State private var isLoading = false
    @State private var isTesting = false
    @State private var apiOptions = [String]()
    @State private var speedResults = [SourceRouteSpeedTestResult]()
    @State private var showsOptions = false

    var body: some View {
        Section {
            LabeledContent {
                TextField(PlatformFeatureSettings.defaultFrontendBaseURL(for: .htManga), text: $apiBaseURL)
                    .multilineTextAlignment(.trailing)
                    .picaxDisablesTextAutocapitalization()
                    .autocorrectionDisabled()
                    .picaxKeyboardType(.url)
                    .onSubmit {
                        normalize()
                    }
            } label: {
                Text("API 地址")
            }

            Button {
                Task {
                    await loadOptions()
                }
            } label: {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("正在获取")
                    }
                } else {
                    Label("更新 API 分流", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isLoading)

            SourceRouteSpeedTestControl(
                actionTitle: "测试 API 分流",
                options: speedTestOptions,
                results: speedResults,
                selectedID: normalizedAPIBaseURL,
                isTesting: isTesting,
                test: {
                    Task { await testAPIOptions() }
                },
                select: { apiBaseURL = $0 }
            )
        } header: {
            Text("绅士漫画")
        } footer: {
            Text("API 地址会影响绅士漫画的列表、详情和图片解析。")
        }
        .confirmationDialog("API 分流", isPresented: $showsOptions, titleVisibility: .visible) {
            ForEach(apiOptions, id: \.self) { option in
                Button(URL(string: option)?.host ?? option) {
                    apiBaseURL = option
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onDisappear {
            normalize()
        }
    }

    @MainActor
    private func testAPIOptions() async {
        guard !isTesting else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            if apiOptions.isEmpty {
                apiOptions = try await service.loadHtMangaAPIBaseURLs()
            }
            speedResults = await service.testHtMangaAPIBaseURLs(apiOptions)
        } catch {
            showMessage("测速失败", error.localizedDescription)
        }
    }

    private var speedTestOptions: [SourceRouteSpeedOption] {
        apiOptions.map { option in
            SourceRouteSpeedOption(id: option, title: URL(string: option)?.host ?? option)
        }
    }

    private var normalizedAPIBaseURL: String {
        PlatformFeatureSettings.normalizedBaseURL(
            apiBaseURL,
            fallback: PlatformFeatureSettings.defaultFrontendBaseURL(for: .htManga)
        )
    }

    @MainActor
    private func loadOptions() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            apiOptions = try await service.loadHtMangaAPIBaseURLs()
            showsOptions = true
        } catch {
            showMessage("更新失败", error.localizedDescription)
        }
    }

    private func normalize() {
        apiBaseURL = PlatformFeatureSettings.normalizedBaseURL(apiBaseURL, fallback: PlatformFeatureSettings.defaultFrontendBaseURL(for: .htManga))
    }
}

private struct PicacgUserCommentsPage: View {
    let service: ComicContentService
    let account: PlatformAccount?

    @State private var comments = [PicacgUserComment]()
    @State private var page = 1
    @State private var pages = 1
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Button("重试") {
                        Task {
                            await reload()
                        }
                    }
                }
            }

            Section {
                if comments.isEmpty && isLoading {
                    HStack {
                        ProgressView()
                        Text("正在加载评论")
                            .foregroundStyle(.secondary)
                    }
                } else if comments.isEmpty {
                    Text("暂无评论")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comments) { comment in
                        ComicDetailNavigationLink(item: comment.comicItem, service: service) {
                            PicacgUserCommentRow(comment: comment)
                        }
                    }

                    if page < pages {
                        Button {
                            Task {
                                await loadMore()
                            }
                        } label: {
                            if isLoading {
                                HStack {
                                    ProgressView()
                                    Text("正在加载")
                                }
                            } else {
                                Text("加载更多")
                            }
                        }
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle("我的评论")
        .task {
            guard comments.isEmpty else { return }
            await reload()
        }
    }

    @MainActor
    private func reload() async {
        comments.removeAll()
        page = 1
        pages = 1
        await load(page: 1, appending: false)
    }

    @MainActor
    private func loadMore() async {
        guard page < pages else { return }
        await load(page: page + 1, appending: true)
    }

    @MainActor
    private func load(page targetPage: Int, appending: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await service.loadPicacgUserComments(account: account, page: targetPage)
            page = data.page
            pages = data.pages
            if appending {
                comments.append(contentsOf: data.comments)
            } else {
                comments = data.comments
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PicacgUserCommentRow: View {
    let comment: PicacgUserComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(comment.comicTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(comment.content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            HStack(spacing: 12) {
                if let timeText = comment.timeText {
                    Text(timeText)
                }
                Label("\(comment.likesCount)", systemImage: comment.isLiked ? "heart.fill" : "heart")
                Label("\(comment.replyCount)", systemImage: "text.bubble")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct EhentaiProfileSelectionPage: View {
    let service: ComicContentService

    @AppStorage(PlatformFeatureSettingsKey.ehentaiProfile) private var selectedProfile = ""
    @State private var profiles = [EhentaiProfile]()
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在加载 Profile")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Button("重试") {
                        Task {
                            await load()
                        }
                    }
                }
            } else {
                Section {
                    ForEach(profiles) { profile in
                        Button {
                            selectedProfile = profile.id
                        } label: {
                            HStack {
                                Text(profile.displayTitle)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedProfile == profile.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle("Profile")
        .task {
            guard profiles.isEmpty else { return }
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            profiles = try await service.loadEhentaiProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum SourceCookieCleaner {
    static func clear(hosts: [String]) {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return }
        for cookie in cookies where hosts.contains(where: { host in
            cookie.domain == host || cookie.domain.hasSuffix(host)
        }) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        URLCache.shared.removeAllCachedResponses()
    }
}
