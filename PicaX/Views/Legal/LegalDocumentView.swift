import SwiftUI

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            LegalDocumentContent(document: document)
                .frame(maxWidth: 720)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
        }
        .background(AppColor.systemBackground.ignoresSafeArea())
        .navigationTitle(document.title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
    }
}

struct LegalDocumentContent: View {
    let document: LegalDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            documentHeader

            Divider()
                .padding(.vertical, 28)

            ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.title3.weight(.semibold))

                    Text(section.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < document.sections.count - 1 {
                    Divider()
                        .padding(.vertical, 24)
                }
            }
        }
        .textSelection(.enabled)
    }

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(document.title)
                .font(.largeTitle.bold())

            Text(document.introduction)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Text("更新日期：2026 年 7 月 24 日")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}

struct LegalDocumentView_Previews: PreviewProvider {
    static var previews: some View {
        PicaxNavigationContainer {
            LegalDocumentView(document: .contentDisclaimer)
        }
    }
}
