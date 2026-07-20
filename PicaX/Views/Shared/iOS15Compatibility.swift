import SwiftUI

struct PicaxNavigationContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        // iOS 16 can enter an update cycle when this hierarchy combines
        // NavigationStack with several nested programmatic destinations.
        if #available(iOS 17.0, *) {
            NavigationStack {
                content
            }
        } else {
            NavigationView {
                content
            }
            .navigationViewStyle(.stack)
        }
        #else
        NavigationStack {
            content
        }
        #endif
    }
}

enum PicaxPresentationDetent: Hashable {
    case medium
    case large
    case height(CGFloat)
}

extension View {
    @ViewBuilder
    func picaxPresentationDetents(
        _ detents: Set<PicaxPresentationDetent>,
        showsDragIndicator: Bool = true
    ) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            presentationDetents(Set(detents.map(\.swiftUIDetent)))
                .presentationDragIndicator(showsDragIndicator ? .visible : .hidden)
        } else {
            self
        }
        #else
        presentationDetents(Set(detents.map(\.swiftUIDetent)))
            .presentationDragIndicator(showsDragIndicator ? .visible : .hidden)
        #endif
    }

    @ViewBuilder
    func picaxSearchSuggestions<Suggestions: View>(
        @ViewBuilder suggestions: () -> Suggestions
    ) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            searchSuggestions(suggestions)
        } else {
            self
        }
        #else
        searchSuggestions(suggestions)
        #endif
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
private extension PicaxPresentationDetent {
    var swiftUIDetent: PresentationDetent {
        switch self {
        case .medium:
            .medium
        case .large:
            .large
        case .height(let height):
            .height(height)
        }
    }
}

struct LabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            SwiftUI.LabeledContent {
                content
            } label: {
                label
            }
        } else {
            legacyContent
        }
        #else
        SwiftUI.LabeledContent {
            content
        } label: {
            label
        }
        #endif
    }

    private var legacyContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            label
            Spacer(minLength: 8)
            content
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension LabeledContent where Label == Text, Content == Text {
    init(_ title: LocalizedStringKey, value: String) {
        self.init {
            Text(value)
        } label: {
            Text(title)
        }
    }
}
