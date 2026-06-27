import SwiftUI

#if os(iOS)
import UIKit
#endif

enum PicaXKeyboardType {
    case asciiCapable
    case emailAddress
    case numberPad
    case url

    #if os(iOS)
    var uiKeyboardType: UIKeyboardType {
        switch self {
        case .asciiCapable:
            .asciiCapable
        case .emailAddress:
            .emailAddress
        case .numberPad:
            .numberPad
        case .url:
            .URL
        }
    }
    #endif
}

extension View {
    @ViewBuilder
    func picaxKeyboardType(_ type: PicaXKeyboardType) -> some View {
        #if os(iOS)
        keyboardType(type.uiKeyboardType)
        #else
        self
        #endif
    }

    @ViewBuilder
    func picaxDisablesTextAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
