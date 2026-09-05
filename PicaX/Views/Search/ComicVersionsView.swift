import SwiftUI

private nonisolated struct ComicVersionGroup: Identifiable, Sendable {
    let id: String
    var items: [ComicListItem]
}

struct ComicVersionsView: View {
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService
    @StateObject private var overrides = StoredCollection<ComicVersionOverride>(key: ComicVersionOverride.storageKey)
    let comics: [ComicListItem]
    let service: ComicContentService
    @State private var groups: [ComicVersionGroup] = []
    @State private var editedItem: ComicListItem?

    private struct SnapshotKey: Hashable {
        let comics: [String]
        let overrides: [ComicVersionOverride]
        let blockingFingerprint: Int
    }

    var body: some View {
        List {
            Section {
                Text("按去除附加信息后的同名标题合并；各版本保留独立的来源、语言和页数。长按条目可纠正分组。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.items, id: \.readingHistoryID) { item in
                        ComicDetailNavigationLink(item: item, service: service) {
                            HStack {
                                ComicCoverView(url: item.coverURL, accentColor: item.accentColor, width: 42, height: 58)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).lineLimit(2)
                                    Text([item.platformTitle, item.language ?? "语言未知", item.pageText ?? "页数未知"].joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu { Button("纠正分组") { editedItem = item } }
                    }
                } header: {
                    Text("\(group.items.first?.title ?? "") · \(group.items.count) 个版本")
                }
            }
        }
        .navigationTitle("多源版本")
        .picaxSensitiveImageContent(!groups.isEmpty)
        .sheet(item: $editedItem) { item in
            ComicVersionOverrideEditor(item: item, store: overrides)
        }
        .task(id: SnapshotKey(comics: comics.map { "\($0.readingHistoryID):\($0.title)" },
                              overrides: overrides.records, blockingFingerprint: blockingKeywords.commonKeywordMatcher.fingerprint)) {
            let comics = comics
            let preferences = overrides.records
            let matcher = blockingKeywords.commonKeywordMatcher
            let work = Task.detached(priority: .userInitiated) {
                let resolver = ComicListTagResolver(comics: comics)
                let overrides = Dictionary(uniqueKeysWithValues: preferences.map { ($0.id, $0) })
                var groups: [ComicVersionGroup] = []
                var groupByKey: [String: Int] = [:]
                for item in comics {
                    try Task.checkCancellation()
                    guard matcher.blockedKeyword(for: item, tagResolver: resolver) == nil else { continue }
                    let preference = overrides[item.readingHistoryID]
                    let keys: [String]
                    if preference?.separates == true {
                        keys = ["item:" + item.readingHistoryID]
                    } else if let manual = preference?.group, !manual.isEmpty {
                        keys = ["manual:" + manual]
                    } else {
                        keys = ComicTitleMatcher.versionGroupingKeys(for: item.title).map { "title:" + $0 }
                    }
                    let index = keys.compactMap { groupByKey[$0] }.first ?? groups.count
                    if index == groups.count {
                        groups.append(ComicVersionGroup(id: item.readingHistoryID, items: []))
                    }
                    groups[index].items.append(item)
                    for key in keys { groupByKey[key] = index }
                }
                return groups
            }
            await withTaskCancellationHandler {
                if let result = try? await work.value, !Task.isCancelled { groups = result }
            } onCancel: { work.cancel() }
        }
    }
}

private struct ComicVersionOverrideEditor: View {
    @Environment(\.dismiss) private var dismiss
    let item: ComicListItem
    let store: StoredCollection<ComicVersionOverride>
    @State private var group = ""
    @State private var separates = false
    var body: some View {
        PicaxNavigationContainer {
            Form {
                Text(item.title)
                Toggle("保持为独立条目", isOn: $separates)
                if !separates {
                    Section {
                        TextField("自定义分组名称", text: $group)
                    } footer: {
                        Text("为需要合并的条目填写相同名称；留空使用自动分组。")
                    }
                }
            }
            .navigationTitle("纠正分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.put(.init(id: item.readingHistoryID, group: group.trimmingCharacters(in: .whitespacesAndNewlines), separates: separates))
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let preference = store.records.first { $0.id == item.readingHistoryID }
            group = preference?.group ?? ""
            separates = preference?.separates ?? false
        }
    }
}

struct OtherComicSourcesPage: View {
    @EnvironmentObject private var accounts: PlatformAccountService
    let item: ComicListItem
    let service: ComicContentService
    @StateObject private var model: ComicSearchViewModel
    @State private var showsProgress = false

    init(item: ComicListItem, service: ComicContentService) {
        self.item = item
        self.service = service
        _model = StateObject(wrappedValue: ComicSearchViewModel(service: service))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading: ProgressView("查找其他来源")
            case .loaded(let results): ComicVersionsView(comics: [item] + results.filter { $0.readingHistoryID != item.readingHistoryID }, service: service)
            case .failed(let message): Text(message).padding()
            }
        }
        .navigationTitle("其他来源")
        .picaxHidesTabBar()
        .toolbar { Button("请求进度") { showsProgress = true } }
        .sheet(isPresented: $showsProgress) {
            ComicSearchProgressSheet(model: model, query: query, target: target) { platform in
                Task { await model.retryFailed(platform: platform, accounts: searchAccounts) }
            }
        }
        .task { await model.search(target: target, keyword: query, accounts: searchAccounts, options: .init()) }
    }

    private var target: ComicSearchTarget { .aggregate(ComicPlatform.onlinePlatforms.filter { $0 != item.platform }) }
    private var query: String { "\"" + ComicTitleMatcher.versionSearchTitle(item.title).replacingOccurrences(of: "\"", with: "") + "\"" }
    private var searchAccounts: [ComicPlatform: PlatformAccount] {
        Dictionary(uniqueKeysWithValues: target.platforms.compactMap { platform in accounts.account(for: platform).map { (platform, $0) } })
    }
}
