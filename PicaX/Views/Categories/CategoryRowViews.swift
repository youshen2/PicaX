import SwiftUI

struct CategoryListRow: View {
    let item: ComicCategoryItem

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(item: item)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(item.platform.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.platform.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(item.platform.accentColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryIconView: View {
    let item: ComicCategoryItem

    var body: some View {
        CachedRemoteImageView(url: coverURL, accentColor: item.platform.accentColor, contentMode: .fill, maxPixelSize: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .clipped()
    }

    private var coverURL: URL? {
        guard let coverURLString = item.coverURLString else { return nil }
        return URL.picaxResolved(from: coverURLString)
    }
}

struct CategoryLoadingSection: View {
    var body: some View {
        Section {
            LoadingStateView(title: "正在加载分类", showsBackground: false)
                .listRowBackground(Color.clear)
        }
    }
}

struct CategoryAutoLoadRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("加载更多分类")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}
