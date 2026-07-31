import SwiftUI

struct SettingsDestinationView: View {
    let route: SettingsRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case .platformAccounts:
            PlatformAccountsSettingsView()
        case .home:
            HomeSettingsView()
        case .explore:
            ExploreSettingsView()
        case .search:
            SearchSettingsView()
        case .comicList:
            ComicListSettingsView()
        case .comicDetail:
            ComicDetailSettingsView()
        case .reader:
            ReaderSettingsView()
        case .downloads:
            DownloadSettingsView()
        case .history:
            HistorySettingsView()
        case .readingDuration:
            ReadingDurationSettingsView()
        case .blockingKeywords:
            BlockingKeywordSettingsView()
        case .storage:
            StorageManagementView()
        case .backup:
            BackupSettingsView()
        case .appDisplay:
            AppDisplaySettingsView()
        case .appBehavior:
            AppBehaviorSettingsView()
        case .watchConnectivity:
            WatchConnectivitySettingsView()
        case .network:
            NetworkSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}
