import SwiftUI

struct AgeRequirementView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State private var showsUnderageMessage = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("18+")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .accessibilityLabel("仅限已满 18 周岁的用户")

                    Text("年龄确认")
                        .font(.title.bold())
                        .padding(.top, 24)

                    Text("PicaX 仅面向已满 18 周岁的用户。应用可能展示来自第三方平台的成人题材内容。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420, alignment: .leading)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 28)
                .padding(.top, max(72, proxy.size.height * 0.12))
                .padding(.bottom, 32)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            confirmationBar
        }
        .background(AppColor.systemBackground.ignoresSafeArea())
        .alert("无法继续", isPresented: $showsUnderageMessage) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("PicaX 仅向已满 18 周岁的用户开放。请关闭应用，并在满足年龄要求后再使用。")
        }
    }

    private var confirmationBar: some View {
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
            .background(.blue, in: Capsule())
            .glassProminentIfAvailable()
            .accessibilityHint("确认年龄并进入应用引导")

            Button("我未满 18 周岁") {
                showsUnderageMessage = true
            }
            .buttonStyle(.plain)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .accessibilityHint("未满 18 周岁无法使用本应用")
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background {
            LinearGradient(
                colors: [
                    .clear,
                    AppColor.systemBackground.opacity(0.96),
                    AppColor.systemBackground
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

struct AgeRequirementView_Previews: PreviewProvider {
    static var previews: some View {
        AgeRequirementView()
            .environmentObject(AppSettings(defaults: .preview))
    }
}
