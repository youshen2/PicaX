import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State private var selection = 0
    @State private var legalConfirmationStep: OnboardingLegalStep?

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
        .sheet(item: $legalConfirmationStep) { step in
            OnboardingLegalConfirmationView(initialStep: step)
        }
        .onAppear {
            guard appSettings.hasAcceptedTerms,
                  !appSettings.hasAcceptedDisclaimer else {
                return
            }
            legalConfirmationStep = .disclaimer
        }
    }

    private func continueTapped() {
        if selection == pages.indices.last {
            legalConfirmationStep = appSettings.hasAcceptedTerms ? .disclaimer : .userAgreement
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
                OnboardingFeature(icon: "network", title: "第三方内容", message: "应用仅提供客户端功能，漫画、图片等内容来自所连接的第三方平台")
            ],
            footnote: "接下来需要确认用户协议与免责声明"
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
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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

private extension View {
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
