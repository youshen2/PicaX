import SwiftUI

struct ContentUnavailableTitleLabel: View {
    private let title: Text
    private let systemImage: String

    init(title: Text, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            title
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
    }
}

struct ContentUnavailableView<TitleLabel: View, Description: View, Actions: View>: View {
    private let label: TitleLabel
    private let description: Description
    private let actions: Actions

    init(
        @ViewBuilder label: () -> TitleLabel,
        @ViewBuilder description: () -> Description = { EmptyView() },
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) {
            SwiftUI.ContentUnavailableView {
                label
            } description: {
                description
            } actions: {
                actions
            }
        } else {
            VStack(spacing: 14) {
                label
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                description
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                actions
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
    }
}

extension ContentUnavailableView where TitleLabel == ContentUnavailableTitleLabel, Description == Text?, Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage name: String, description: Text? = nil) {
        self.init {
            ContentUnavailableTitleLabel(title: Text(title), systemImage: name)
        } description: {
            description
        } actions: {
            EmptyView()
        }
    }

    init<S>(_ title: S, systemImage name: String, description: Text? = nil) where S: StringProtocol {
        self.init {
            ContentUnavailableTitleLabel(title: Text(String(title)), systemImage: name)
        } description: {
            description
        } actions: {
            EmptyView()
        }
    }
}
