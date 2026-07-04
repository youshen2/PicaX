#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct PicaXDownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var progress: Double
        var completedUnitCount: Int
        var totalUnitCount: Int
        var activeTaskCount: Int
        var queuedTaskCount: Int

        var clippedProgress: Double {
            min(max(progress, 0), 1)
        }

        var progressText: String {
            "\(Int((clippedProgress * 100).rounded()))%"
        }

        var unitText: String {
            "\(completedUnitCount)/\(max(totalUnitCount, 1))"
        }
    }

    let activityID: String
}
#endif
