import SwiftUI

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
        if #available(iOS 16.0, *) {
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
