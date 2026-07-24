import SwiftUI

enum OnboardingLegalStep: String, Identifiable, Hashable {
    case userAgreement
    case disclaimer

    var id: String { rawValue }

    var document: LegalDocument {
        switch self {
        case .userAgreement:
            .userAgreement
        case .disclaimer:
            .contentDisclaimer
        }
    }
}

struct OnboardingLegalConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @State private var step: OnboardingLegalStep

    init(initialStep: OnboardingLegalStep) {
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        PicaxNavigationContainer {
            ZStack {
                AppColor.systemBackground
                    .ignoresSafeArea()

                documentScrollView
                    .id(step)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                confirmationBar
            }
            .navigationTitle("协议确认")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .picaxPresentationDetents([.large])
    }

    private var documentScrollView: some View {
        ScrollView {
            LegalDocumentContent(document: step.document)
                .frame(maxWidth: 720)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
        }
    }

    private var confirmationBar: some View {
        VStack(spacing: 12) {
            Button(action: acceptCurrentStep) {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.blue, in: Capsule())
            .glassProminentIfAvailable()

            Button("不同意") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)

            Text("同意后仍可在“设置 > 关于”中查看这些文档。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background {
            LinearGradient(
                colors: [.clear, AppColor.systemBackground.opacity(0.96), AppColor.systemBackground],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .userAgreement:
            "同意并查看免责声明"
        case .disclaimer:
            "同意并继续"
        }
    }

    private func acceptCurrentStep() {
        switch step {
        case .userAgreement:
            appSettings.acceptTerms()
            step = .disclaimer
        case .disclaimer:
            appSettings.acceptDisclaimerAndCompleteOnboarding()
            dismiss()
        }
    }
}

struct OnboardingLegalConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingLegalConfirmationView(initialStep: .disclaimer)
            .environmentObject(AppSettings(defaults: .preview))
    }
}
