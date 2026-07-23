import SwiftUI

struct ComicDetailTransitionID: Hashable {
    private let platformID: String
    private let comicID: String

    init(_ item: ComicListItem) {
        platformID = item.platform.id
        comicID = item.id
    }
}

struct ComicDetailTransitionSource {
    let id: ComicDetailTransitionID
    let namespace: Namespace.ID

    init(item: ComicListItem, namespace: Namespace.ID) {
        id = ComicDetailTransitionID(item)
        self.namespace = namespace
    }
}

struct ComicDetailNavigationLink<Label: View>: View {
    private let item: ComicListItem
    private let service: ComicContentService

    @Namespace private var transitionNamespace

    private let label: () -> Label

    init(
        item: ComicListItem,
        service: ComicContentService,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.item = item
        self.service = service
        self.label = label
    }

    var body: some View {
        NavigationLink {
            ComicDetailPage(item: item, service: service)
                .picaxComicDetailZoomDestination(
                    sourceID: transitionID,
                    in: transitionNamespace
                )
        } label: {
            label()
                .picaxComicDetailTransitionSource(
                    id: transitionID,
                    in: transitionNamespace
                )
        }
    }

    private var transitionID: ComicDetailTransitionID {
        ComicDetailTransitionID(item)
    }
}

extension ToolbarItemPlacement {
    static var picaxTopBarLeading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    static var picaxTopBarTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarTrailing
        #endif
    }
}

extension View {
    func picaxComicDetailTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(
            ComicDetailTransitionSourceModifier(
                id: id,
                namespace: namespace
            )
        )
    }

    fileprivate func picaxComicDetailZoomDestination<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(
            ComicDetailZoomDestinationModifier(
                sourceID: sourceID,
                namespace: namespace
            )
        )
    }

    @ViewBuilder
    func picaxNavigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func picaxNavigationDestination<Item, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        #if os(iOS)
        // Keep the destination mechanism aligned with PicaxNavigationContainer.
        if #available(iOS 17.0, *) {
            navigationDestination(isPresented: item.isPresent()) {
                destinationContent(item: item, destination: destination)
            }
        } else {
            background {
                NavigationLink(isActive: item.isPresent()) {
                    destinationContent(item: item, destination: destination)
                } label: {
                    EmptyView()
                }
                .hidden()
            }
        }
        #else
        navigationDestination(isPresented: item.isPresent()) {
            destinationContent(item: item, destination: destination)
        }
        #endif
    }

    @ViewBuilder
    func picaxComicDetailDestination(
        item: Binding<ComicListDetailRequest?>,
        in namespace: Namespace.ID,
        service: ComicContentService
    ) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            navigationDestination(isPresented: item.isPresent()) {
                destinationContent(item: item) { request in
                    ComicDetailPage(item: request.item, service: service)
                        .picaxComicDetailZoomDestination(
                            sourceID: ComicDetailTransitionID(request.item),
                            in: namespace
                        )
                }
            }
        } else {
            picaxNavigationDestination(item: item) { request in
                ComicDetailPage(item: request.item, service: service)
            }
        }
        #else
        picaxNavigationDestination(item: item) { request in
            ComicDetailPage(item: request.item, service: service)
        }
        #endif
    }

    @ViewBuilder
    private func destinationContent<Item, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: (Item) -> Destination
    ) -> some View {
        if let wrappedItem = item.wrappedValue {
            destination(wrappedItem)
        } else {
            EmptyView()
        }
    }
}

private struct ComicDetailTransitionSourceModifier<ID: Hashable>: ViewModifier {
    @Environment(\.picaxUsesSmoothComicDetailTransitions)
    private var usesSmoothComicDetailTransitions

    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), usesSmoothComicDetailTransitions {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct ComicDetailZoomDestinationModifier<ID: Hashable>: ViewModifier {
    @Environment(\.picaxUsesSmoothComicDetailTransitions)
    private var usesSmoothComicDetailTransitions

    let sourceID: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), usesSmoothComicDetailTransitions {
            content.navigationTransition(
                .zoom(sourceID: sourceID, in: namespace)
            )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct PicaxUsesSmoothComicDetailTransitionsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var picaxUsesSmoothComicDetailTransitions: Bool {
        get { self[PicaxUsesSmoothComicDetailTransitionsKey.self] }
        set { self[PicaxUsesSmoothComicDetailTransitionsKey.self] = newValue }
    }
}

private extension Binding {
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { isPresent in
                if !isPresent {
                    wrappedValue = nil
                }
            }
        )
    }
}
