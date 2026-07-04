#if os(iOS)
import Foundation
import UserNotifications

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class DownloadProgressPresentationService {
    private static let progressNotificationID = "picax.download.progress"
    private static let notificationThreadID = "picax.downloads"
    private static let activityID = "picax.download.progress"
    private static let notificationUpdateInterval: TimeInterval = 1.5

    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private var lastNotificationSnapshot: DownloadProgressPresentationSnapshot?
    private var lastNotificationDate = Date.distantPast
    private var pendingNotificationSnapshot: DownloadProgressPresentationSnapshot?
    private var scheduledNotificationTask: Task<Void, Never>?

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private typealias DownloadActivity = Activity<PicaXDownloadActivityAttributes>
    private var lastActivityState: PicaXDownloadActivityAttributes.ContentState?
    #endif

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func update(tasks: [ComicDownloadTask]) {
        let snapshot = DownloadProgressPresentationSnapshot(tasks: tasks)

        if defaults.bool(forKey: DownloadSettingsKey.showsProgressNotifications) {
            updateNotification(snapshot: snapshot)
        } else {
            clearNotification()
        }

        if defaults.bool(forKey: DownloadSettingsKey.showsProgressLiveActivity) {
            updateLiveActivity(snapshot: snapshot)
        } else {
            endLiveActivity()
        }
    }

    private func updateNotification(snapshot: DownloadProgressPresentationSnapshot?) {
        pendingNotificationSnapshot = snapshot

        guard let snapshot else {
            clearNotification()
            return
        }

        let elapsed = Date().timeIntervalSince(lastNotificationDate)
        let shouldPresentImmediately = lastNotificationSnapshot == nil
            || lastNotificationSnapshot?.activeTaskID != snapshot.activeTaskID
            || lastNotificationSnapshot?.statusText != snapshot.statusText
            || abs((lastNotificationSnapshot?.progress ?? 0) - snapshot.progress) >= 0.04
            || elapsed >= Self.notificationUpdateInterval

        if shouldPresentImmediately {
            scheduledNotificationTask?.cancel()
            scheduledNotificationTask = nil
            presentPendingNotification()
        } else if scheduledNotificationTask == nil {
            let delay = max(Self.notificationUpdateInterval - elapsed, 0.2)
            scheduledNotificationTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.presentPendingNotification()
            }
        }
    }

    private func presentPendingNotification() {
        scheduledNotificationTask = nil
        guard let snapshot = pendingNotificationSnapshot else {
            clearNotification()
            return
        }

        pendingNotificationSnapshot = nil
        lastNotificationSnapshot = snapshot
        lastNotificationDate = Date()

        Task {
            guard await notificationAuthorizationAllowsPresentation() else { return }
            let content = UNMutableNotificationContent()
            content.title = "漫画下载中"
            content.subtitle = snapshot.queueText
            content.body = "\(snapshot.title) · \(snapshot.statusText)"
            content.threadIdentifier = Self.notificationThreadID
            content.targetContentIdentifier = Self.progressNotificationID
            content.relevanceScore = min(max(snapshot.progress, 0), 1)

            if #available(iOS 15.0, *) {
                content.interruptionLevel = .passive
            }

            let request = UNNotificationRequest(
                identifier: Self.progressNotificationID,
                content: content,
                trigger: nil
            )
            notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.progressNotificationID])
            try? await notificationCenter.add(request)
        }
    }

    private func clearNotification() {
        pendingNotificationSnapshot = nil
        scheduledNotificationTask?.cancel()
        scheduledNotificationTask = nil
        lastNotificationSnapshot = nil
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.progressNotificationID])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.progressNotificationID])
    }

    private func notificationAuthorizationAllowsPresentation() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func updateLiveActivity(snapshot: DownloadProgressPresentationSnapshot?) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }

        Task {
            guard let snapshot else {
                await endLiveActivityIfAvailable()
                return
            }

            let state = PicaXDownloadActivityAttributes.ContentState(
                title: snapshot.title,
                detail: snapshot.statusText,
                progress: snapshot.progress,
                completedUnitCount: snapshot.completedUnitCount,
                totalUnitCount: snapshot.totalUnitCount,
                activeTaskCount: snapshot.activeTaskCount,
                queuedTaskCount: snapshot.queuedTaskCount
            )
            lastActivityState = state

            if let activity = DownloadActivity.activities.first {
                await activity.update(ActivityContent(state: state, staleDate: nil))
                return
            }

            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = PicaXDownloadActivityAttributes(activityID: Self.activityID)
            _ = try? DownloadActivity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        Task {
            await endLiveActivityIfAvailable()
        }
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func endLiveActivityIfAvailable() async {
        let fallbackState = PicaXDownloadActivityAttributes.ContentState(
            title: "下载已结束",
            detail: "没有正在进行的下载任务",
            progress: 1,
            completedUnitCount: 1,
            totalUnitCount: 1,
            activeTaskCount: 0,
            queuedTaskCount: 0
        )
        let content = ActivityContent(state: lastActivityState ?? fallbackState, staleDate: nil)

        for activity in DownloadActivity.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        lastActivityState = nil
    }
    #endif
}

private struct DownloadProgressPresentationSnapshot: Equatable {
    let activeTaskID: String
    let title: String
    let statusText: String
    let progress: Double
    let completedUnitCount: Int
    let totalUnitCount: Int
    let activeTaskCount: Int
    let queuedTaskCount: Int

    init?(tasks: [ComicDownloadTask]) {
        let visibleTasks = tasks.filter { task in
            task.status == .downloading || task.status == .queued
        }
        guard !visibleTasks.isEmpty else { return nil }

        let preferredTask = visibleTasks.first(where: { $0.status == .downloading }) ?? visibleTasks[0]
        activeTaskID = preferredTask.id
        title = preferredTask.item.title
        statusText = preferredTask.statusText
        activeTaskCount = visibleTasks.filter { $0.status == .downloading }.count
        queuedTaskCount = visibleTasks.filter { $0.status == .queued }.count

        let completedUnits = visibleTasks.reduce(0.0) { result, task in
            result + Double(task.completedChapterIndexes.count) + Self.currentPageProgress(for: task)
        }
        let totalUnits = visibleTasks.reduce(0) { result, task in
            result + max(task.chapterIndexes.count, 1)
        }

        completedUnitCount = min(Int(floor(completedUnits)), max(totalUnits, 1))
        totalUnitCount = max(totalUnits, 1)
        progress = min(max(completedUnits / Double(max(totalUnits, 1)), 0), 1)
    }

    var queueText: String {
        var parts: [String] = []
        if activeTaskCount > 0 {
            parts.append("\(activeTaskCount) 个下载中")
        }
        if queuedTaskCount > 0 {
            parts.append("\(queuedTaskCount) 个等待")
        }
        parts.append("\(Int((progress * 100).rounded()))%")
        return parts.joined(separator: " · ")
    }

    private static func currentPageProgress(for task: ComicDownloadTask) -> Double {
        guard task.status == .downloading, task.currentPageCount > 0 else {
            return 0
        }
        return min(max(Double(task.currentPageIndex) / Double(task.currentPageCount), 0), 1)
    }
}
#endif
