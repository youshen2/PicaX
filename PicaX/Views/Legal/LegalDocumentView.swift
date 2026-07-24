import SwiftUI

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            LegalDocumentContent(document: document)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
        }
        .background(AppColor.groupedBackground.ignoresSafeArea())
        .navigationTitle(document.title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
    }
}

struct LegalDocumentContent: View {
    let document: LegalDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label(document.title, systemImage: document.systemImage)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(document.introduction)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)

                Text("更新日期：2026 年 7 月 24 日")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColor.secondaryGroupedBackground,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )

            ForEach(document.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.headline)

                    Text(section.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    AppColor.secondaryGroupedBackground,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
        .textSelection(.enabled)
    }
}

struct LegalDocumentView_Previews: PreviewProvider {
    static var previews: some View {
        PicaxNavigationContainer {
            LegalDocumentView(document: .contentDisclaimer)
        }
    }
}
