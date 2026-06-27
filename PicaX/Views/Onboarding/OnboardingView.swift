import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State private var selection = 0
    @State private var isShowingTerms = false

    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            AppColor.systemBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingTopBar(
                    canGoBack: selection > 0,
                    back: {
                        withAnimation(.snappy) {
                            selection = max(selection - 1, 0)
                        }
                    }
                )

                TabView(selection: $selection) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .picaxPageTabViewStyle()
            }

            VStack {
                Spacer()
                OnboardingBottomBar(
                    primaryTitle: "继续",
                    secondaryTitle: nil,
                    primaryAction: continueTapped,
                    secondaryAction: nil
                )
            }
        }
        .sheet(isPresented: $isShowingTerms) {
            TermsSheet(
                agree: {
                    appSettings.completeOnboarding()
                    isShowingTerms = false
                },
                disagree: {
                    isShowingTerms = false
                }
            )
        }
    }

    private func continueTapped() {
        if selection == pages.indices.last {
            isShowingTerms = true
        } else {
            withAnimation(.snappy) {
                selection += 1
            }
        }
    }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let imageName: String?
    let title: String
    let subtitle: String
    let features: [OnboardingFeature]
    let footnote: String

    static let pages = [
        OnboardingPage(
            icon: "sparkles",
            imageName: "AppLogo",
            title: "PicaX",
            subtitle: "把阅读、收藏和发现放在一个更顺手的阅读入口里。",
            features: [
                OnboardingFeature(icon: "books.vertical", title: "原生界面", message: "专为 iOS 开发，适配 iOS26+ 液态玻璃"),
                OnboardingFeature(icon: "sparkle.magnifyingglass", title: "集中探索", message: "集 哔咔漫画、禁漫天堂、绅士漫画、NHhentai、Ehentai 于一体")
            ],
            footnote: "接下来需要进行条款确认"
        ),
    ]
}

private struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
}

private struct OnboardingTopBar: View {
    let canGoBack: Bool
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassPlainIfAvailable()
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 28)

            OnboardingIconView(page: page)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 58)

            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 5)

            Text(page.subtitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 20) {
                ForEach(page.features) { feature in
                    OnboardingFeatureRow(feature: feature)
                }
            }

            Spacer()

            Text(page.footnote)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 128)
        }
        .padding(.horizontal, 34)
    }
}

private struct OnboardingIconView: View {
    let page: OnboardingPage

    var body: some View {
        Group {
            if let imageName = page.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: page.icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 84, height: 84)
        .background(
            LinearGradient(
                colors: [.pink, .cyan, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }
}

private struct OnboardingFeatureRow: View {
    let feature: OnboardingFeature

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingBottomBar: View {
    let primaryTitle: String
    let secondaryTitle: String?
    let primaryAction: () -> Void
    let secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 13) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.blue, in: Capsule())
            .glassProminentIfAvailable()

            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .glassPlainIfAvailable()
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [.clear, AppColor.systemBackground.opacity(0.92), AppColor.systemBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private struct TermsSheet: View {
    let agree: () -> Void
    let disagree: () -> Void
    @State private var isShowingEmailUnavailable = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.systemBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("条款与条件")
                            .font(.system(size: 25, weight: .bold))
                            .padding(.top, 30)

                        Button {
                            isShowingEmailUnavailable = true
                        } label: {
                            Text("通过电子邮件发送")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .glassPlainIfAvailable()

                        TermsCard()

                        Spacer(minLength: 124)
                    }
                    .padding(.horizontal, 30)
                }

                VStack {
                    Spacer()
                    TermsBottomBar(agree: agree, disagree: disagree)
                }
            }
            .toolbar {
                ToolbarItem(placement: .picaxTopBarTrailing) {
                    Button(action: disagree) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassPlainIfAvailable()
                }
            }
        }
        .alert("哦吼", isPresented: $isShowingEmailUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("这是一个离线软件，我们做不到发送邮件。")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct TermsCard: View {
    private let sections = [
        TermsSection(
            title: "1. 服务说明",
            body: "PicaX 是一个用于集成阅读、收藏、发现和分类等内容功能的客户端工具，具体能力以应用实际内容为准。"
        ),
        TermsSection(
            title: "2. 账号与本地数据",
            body: "用户可以在应用内保存平台登录状态，账号登录信息存储在本机，用于恢复对应来源的登录状态。请妥善保管你的设备；因设备丢失、系统清理、卸载应用或用户主动删除账号信息导致的数据丢失，由用户自行承担。"
        ),
        TermsSection(
            title: "3. 使用规则",
            body: "用户承诺仅在合法、合规、合理的范围内使用本应用，不利用本应用进行侵犯他人权益、规避平台限制、传播违法内容、破坏服务稳定性或其他不当行为。你应自行确认所在地区关于内容访问、下载、存储和分享的法律要求。"
        ),
        TermsSection(
            title: "4. 内容来源与责任",
            body: "PicaX 本身不保证第三方内容的完整性、准确性、可用性或持续可访问性。若应用未来接入第三方内容或服务，相关内容的权利、规则和可用性由对应来源负责。"
        ),
        TermsSection(
            title: "5. 隐私与权限",
            body: "应用会尽量只请求实现功能所必需的权限，当前引导和账号流程不需要发送电子邮件，也不会因为用户点击“通过电子邮件发送”而实际发送内容。"
        ),
        TermsSection(
            title: "6. 风险提示",
            body: "本应用仍处于早期开发阶段，可能存在功能缺失、数据结构调整、界面变化或兼容性问题。用户理解并同意在使用过程中自行备份重要数据，并接受因测试、升级或系统限制带来的不稳定风险。"
        ),
        TermsSection(
            title: "7. 协议变更",
            body: "我们可能会根据功能变化更新本协议。更新后的协议会在应用内展示；用户继续使用应用，即表示接受更新后的内容。如果用户不同意更新内容，可以停止使用应用。"
        ),
        TermsSection(
            title: "8. 终止使用",
            body: "如果用户不同意本协议，可以选择“不同意”并停止进入后续流程。"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("重要信息")
                    .font(.headline)
                Text("在使用 PicaX 之前，请阅读以下条款。点击同意表示你理解并接受这些条件。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("A. PicaX 用户协议")
                    .font(.headline)
                Spacer()
                Image(systemName: "doc.text")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            Divider()

            Text("请先仔细阅读下列协议，再使用 PicaX。点击“同意”表示你已经理解并接受本协议全部内容。")
                .font(.subheadline.weight(.semibold))
                .lineSpacing(4)

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.subheadline.weight(.bold))
                    Text(section.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
            }
        }
        .padding(20)
        .background(AppColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20))
        .glassPanelIfAvailable(cornerRadius: 20)
    }
}

private struct TermsSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

private struct TermsBottomBar: View {
    let agree: () -> Void
    let disagree: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: agree) {
                Text("同意")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.blue, in: Capsule())
            .glassProminentIfAvailable()

            Button(action: disagree) {
                Text("不同意")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)  
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .glassPlainIfAvailable()
        }
        .padding(.horizontal, 34)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background {
            LinearGradient(
                colors: [.clear, AppColor.systemBackground.opacity(0.95), AppColor.systemBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private extension View {
    @ViewBuilder
    func glassPanelIfAvailable(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func glassPlainIfAvailable() -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(AppSettings(defaults: .preview))
    }
}
