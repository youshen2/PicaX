import SwiftUI

struct LoadingStateView: View {
    let title: String
    var message = "请稍候"
    var showsBackground = true

    var body: some View {
        if showsBackground {
            content
                .background(AppColor.groupedBackground)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.primary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
    }
}
