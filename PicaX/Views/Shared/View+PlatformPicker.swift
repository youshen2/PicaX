import SwiftUI

extension View {
    @ViewBuilder
    func picaxPlatformPickerStyle() -> some View {
        #if os(macOS)
        pickerStyle(.menu)
        #else
        if #available(iOS 16.0, *) {
            pickerStyle(.navigationLink)
        } else {
            pickerStyle(.menu)
        }
        #endif
    }
}
