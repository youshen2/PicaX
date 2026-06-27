import SwiftUI

enum AppColor {
    static var systemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var groupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    static var secondaryGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }

    static var tertiaryGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.18)
        #else
        Color(.tertiarySystemGroupedBackground)
        #endif
    }
}
