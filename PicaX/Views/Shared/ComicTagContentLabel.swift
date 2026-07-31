import SwiftUI

struct ComicTagContentLabel: View {
    private let content: MarkdownImageTagContent
    let color: Color
    let font: Font
    let imageSize: CGFloat

    init(
        _ source: String,
        color: Color,
        font: Font = .caption2.weight(.medium),
        imageSize: CGFloat = 18
    ) {
        content = MarkdownImageTagContent(source)
        self.color = color
        self.font = font
        self.imageSize = imageSize
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(content.segments.indices, id: \.self) { index in
                segment(content.segments[index])
            }
        }
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    @ViewBuilder
    private func segment(_ segment: MarkdownImageTagContent.Segment) -> some View {
        switch segment {
        case .text(let text):
            Text(verbatim: text)
        case .image:
            if let url = segment.imageURL {
                CachedRemoteImageView(
                    url: url,
                    accentColor: color,
                    contentMode: .fill,
                    maxPixelSize: max(Int(imageSize * 3), 48),
                    placeholderSystemImage: "photo"
                )
                .frame(width: imageSize, height: imageSize)
                .clipShape(RoundedRectangle(cornerRadius: imageSize * 0.22, style: .continuous))
            }
        }
    }
}
