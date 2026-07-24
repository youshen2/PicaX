import SwiftUI

struct AgeRequirementView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State private var showsUnderageMessage = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                
                VStack(spacing: 0) {
                    Spacer(minLength: max(32, proxy.size.height * 0.08))

                    VStack(spacing: 14) {
                        Text("年龄确认")
                            .font(.system(size: 32, weight: .bold))

                        Text("PicaX 提供的部分内容可能不适合未成年人。使用本应用前，请确认你已年满 18 周岁。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 28)

                    requirementCard

                    Spacer(minLength: 40)

                    actionButtons
                }
                .frame(minHeight: proxy.size.height)
                .padding(.horizontal, 30)
                .padding(.bottom, 18)
            }
        }
        .alert("无法继续", isPresented: $showsUnderageMessage) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("本应用仅面向已满 18 周岁的用户。请关闭应用。")
        }
    }

    private var background: some View {
        ZStack {
            AppColor.systemBackground

            RadialGradient(
                colors: [
                    Color.red.opacity(0.16),
                    Color.orange.opacity(0.06),
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var requirementCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("仅限成年人")
                    .font(.headline)

                Text("继续即表示你确认自己已满 18 周岁，并会遵守所在地区适用的法律法规。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            AppColor.secondaryGroupedBackground,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                appSettings.confirmAdultAge()
            } label: {
                Text("我已满 18 周岁")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.red, in: Capsule())
            .glassProminentIfAvailable(tint: .red)
            .accessibilityHint("确认后进入应用引导")

            Button {
                showsUnderageMessage = true
            } label: {
                Text("我未满 18 周岁")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityHint("未满 18 周岁无法使用本应用")
        }
    }
}

struct AgeRequirementView_Previews: PreviewProvider {
    static var previews: some View {
        AgeRequirementView()
            .environmentObject(AppSettings(defaults: .preview))
    }
}
