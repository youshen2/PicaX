import SwiftUI

struct ReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let releaseNotes: AppReleaseNotes

    var body: some View {
        PicaxNavigationContainer {
            ReleaseNotesView(
                releaseNotes: releaseNotes,
                currentVersion: releaseNotes.version
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始体验") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
