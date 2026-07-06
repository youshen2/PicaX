import SwiftUI

private struct PicaXSensitiveImageContentModifier: ViewModifier {
    @AppStorage(AppBehaviorSettingsKey.marksImageContentAsSensitive) private var marksImageContentAsSensitive = false
    let containsImageContent: Bool

    func body(content: Content) -> some View {
        content.privacySensitive(marksImageContentAsSensitive && containsImageContent)
    }
}

extension View {
    func picaxSensitiveImageContent(_ containsImageContent: Bool = true) -> some View {
        modifier(PicaXSensitiveImageContentModifier(containsImageContent: containsImageContent))
    }
}
