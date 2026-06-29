import SwiftUI

struct WatchValueRow: View {
    let title: String
    let subtitle: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct WatchComicRow: View {
    let item: WatchComicItem

    var body: some View {
        HStack(spacing: 8) {
            WatchCoverThumbnail(url: item.coverURL, width: 38, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !item.tags.isEmpty {
                    Text(item.tags.prefix(3).joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct WatchCoverThumbnail: View {
    let url: URL?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        WatchRemoteImageView(url: url, contentMode: .fill, placeholderFont: .title3)
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct WatchRemoteImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderFont: Font = .title3

    @State private var localURL: URL?
    @State private var failed = false
    @State private var didRetryDisplayFailure = false

    var body: some View {
        Group {
            if let localURL {
                AsyncImage(url: localURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.7)
                    case .failure:
                        if failed {
                            placeholder
                        } else {
                            ProgressView()
                                .scaleEffect(0.7)
                                .task(id: localURL.absoluteString) {
                                    await reloadAfterDisplayFailure()
                                }
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else if failed {
                placeholder
            } else {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .task(id: url?.absoluteString ?? "") {
            await load()
        }
    }

    @MainActor
    private func load() async {
        localURL = nil
        failed = false
        didRetryDisplayFailure = false
        guard let url else {
            failed = true
            return
        }
        do {
            localURL = try await WatchImageCacheService.cachedFileURL(for: url.absoluteString)
        } catch {
            failed = true
        }
    }

    @MainActor
    private func reloadAfterDisplayFailure() async {
        guard !didRetryDisplayFailure, let url else {
            failed = true
            return
        }
        didRetryDisplayFailure = true
        do {
            localURL = try await WatchImageCacheService.cachedFileURL(for: url.absoluteString, forceRefresh: true)
            failed = false
        } catch {
            localURL = nil
            failed = true
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(placeholderFont)
            .foregroundStyle(.secondary)
    }
}

struct WatchEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct WatchLoadStateSection<Value, Content: View>: View {
    let title: String
    let state: WatchPageState<Value>
    let emptyTitle: String
    let emptySystemImage: String
    let isEmpty: (Value) -> Bool
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Section(title) {
            switch state {
            case .idle, .loading:
                ProgressView()
            case .loaded(let value):
                if isEmpty(value) {
                    WatchEmptyRow(title: emptyTitle, systemImage: emptySystemImage)
                } else {
                    content(value)
                }
            case .failed(let message):
                WatchValueRow(title: "加载失败", subtitle: message, systemImage: "exclamationmark.triangle", tint: .orange)
            }
        }
    }
}

extension WatchComicPlatform {
    var watchColor: Color {
        switch accentColorName {
        case "pink":
            .pink
        case "orange":
            .orange
        case "red":
            .red
        case "purple":
            .purple
        case "blue":
            .blue
        case "teal":
            .teal
        default:
            .accentColor
        }
    }
}
