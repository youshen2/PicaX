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
            guard totalUnitCount > 1 else { return "" }
            return "\(completedUnitCount)/\(max(totalUnitCount, 1)) 章"
        }

        var queueText: String {
            var parts: [String] = []
            if activeTaskCount > 0 {
                parts.append("\(activeTaskCount) 个下载中")
            }
            if queuedTaskCount > 0 {
                parts.append("\(queuedTaskCount) 个等待")
            }
            return parts.joined(separator: " · ")
        }
    }

    let activityID: String
}
#endif
