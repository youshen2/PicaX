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
            AsyncImage(url: item.coverURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: item.platform.systemImage)
                    .font(.title3)
                    .foregroundStyle(item.platform.watchColor)
            }
            .frame(width: 38, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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
