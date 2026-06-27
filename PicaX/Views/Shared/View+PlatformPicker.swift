import SwiftUI

extension View {
    @ViewBuilder
    func picaxPlatformPickerStyle() -> some View {
        #if os(macOS)
        pickerStyle(.menu)
        #else
        pickerStyle(.navigationLink)
        #endif
    }
}
