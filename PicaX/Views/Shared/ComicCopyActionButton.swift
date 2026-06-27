import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ComicCopyActionButton: View {
    let item: ComicListItem
    @State private var copiedAction: ComicCopyAction?

    var body: some View {
        Group {
            if let action = item.copyAction {
                Button {
                    copy(action)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.title)
                                .foregroundStyle(.primary)

                            Text(action.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        Image(systemName: action.systemImage)
                            .foregroundStyle(item.accentColor)
                            .frame(width: 24)
                    }
                }
                .buttonStyle(.plain)
                .alert(copiedAction?.copiedTitle ?? "已复制", isPresented: copiedBinding) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text(copiedAction?.value ?? "")
                }
            }
        }
    }

    private var copiedBinding: Binding<Bool> {
        Binding {
            copiedAction != nil
        } set: { isPresented in
            if !isPresented {
                copiedAction = nil
            }
        }
    }

    private func copy(_ action: ComicCopyAction) {
        #if os(iOS)
        UIPasteboard.general.string = action.value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(action.value, forType: .string)
        #endif
        copiedAction = action
    }
}
