import SwiftUI

struct ComicSearchProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ComicSearchViewModel
    let query: String
    let target: ComicSearchTarget
    let onRetry: (ComicPlatform) -> Void

    var body: some View {
        PicaxNavigationContainer {
            List {
                Section("表达式预览") {
                    switch preview {
                    case .success(let clauses):
                        Text("\(clauses.count) 个组合，\(clauses.count * target.platforms.count) 个首轮请求")
                            .foregroundStyle(.secondary)
                        ForEach(Array(clauses.enumerated()), id: \.offset) { index, clause in
                            Text("\(index + 1). \(clause.displayKeyword)")
                        }
                    case .failure(let error):
                        Text(error.localizedDescription).foregroundStyle(.red)
                    }
                }
                ForEach(target.platforms) { platform in
                    Section(platform.title) {
                        ForEach(model.requests.filter { $0.platform == platform }) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.clause.displayKeyword)
                                HStack {
                                    Text("第 \(request.page) 页")
                                    switch request.status {
                                    case .queued: Text("等待中")
                                    case .loading: ProgressView(); Text("搜索中")
                                    case .loaded(let count): Text("返回 \(count) 项")
                                    case .failed(let message): Text(message).foregroundStyle(.red)
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if model.requests.contains(where: {
                            if case .failed = $0.status { return $0.platform == platform }; return false
                        }) {
                            Button("重试此平台失败的请求") { onRetry(platform) }
                                .disabled(model.isSearching || model.isLoadingMore)
                        }
                    }
                }
            }
            .navigationTitle("搜索预览与进度")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private var preview: Result<[ComicSearchClause], Error> {
        Result { try ComicSearchExpressionParser.clauses(from: query) }
    }
}
