import SwiftUI

struct BlockingKeywordSettingsView: View {
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService

    @State private var selectedScope: BlockingKeywordScope = .common
    @State private var showsDescendingOrder = true
    @State private var addScope: BlockingKeywordScope?
    @State private var editedRule: BlockingRuleEditRequest?

    private var displayedKeywords: [String] {
        let keywords = blockingKeywords.keywords(for: selectedScope)
        return showsDescendingOrder ? Array(keywords.reversed()) : keywords
    }

    private var scopeFooter: String {
        switch selectedScope {
        case .common:
            "通用屏蔽词会在漫画列表加载后生效，支持 title:、uploader:、tag: 前缀；未带前缀时匹配标题、作者和标签。"
        case .jmComic:
            "JMComic 专用屏蔽词会在 JM 搜索时自动追加为排除关键词。"
        }
    }

    var body: some View {
        List {
            Section {
                Picker("分区", selection: $selectedScope) {
                    ForEach(BlockingKeywordScope.allCases) { scope in
                        Text(scope.title)
                            .tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(scopeFooter)
            }

            Section(selectedScope.title) {
                if displayedKeywords.isEmpty {
                    ContentUnavailableView("暂无屏蔽词", systemImage: "eye.slash")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedKeywords, id: \.self) { keyword in
                        Toggle(isOn: Binding(
                            get: { blockingKeywords.isEnabled(keyword, scope: selectedScope) },
                            set: { blockingKeywords.setEnabled($0, keyword: keyword, scope: selectedScope) }
                        )) {
                            Button(keyword) {
                                editedRule = BlockingRuleEditRequest(keyword: keyword, scope: selectedScope)
                            }.buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button("编辑") { editedRule = BlockingRuleEditRequest(keyword: keyword, scope: selectedScope) }
                        }
                    }
                    .onDelete(perform: removeKeywords)
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("关键词屏蔽")
        .picaxHidesTabBar()
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Button(action: toggleDisplayOrder) {
                    Image(systemName: showsDescendingOrder ? "arrow.down" : "arrow.up")
                }
                .accessibilityLabel("切换显示顺序")

                Button(action: presentAddSheet) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加屏蔽词")
            }
        }
        .sheet(item: $editedRule) { request in
            BlockingKeywordAddSheet(scope: request.scope, original: request.keyword)
        }
        .sheet(item: $addScope) { scope in
            BlockingKeywordAddSheet(scope: scope)
        }
    }

    private func toggleDisplayOrder() {
        showsDescendingOrder.toggle()
    }

    private func presentAddSheet() {
        addScope = selectedScope
    }

    private func removeKeywords(at offsets: IndexSet) {
        blockingKeywords.remove(
            at: offsets,
            displayedKeywords: displayedKeywords,
            scope: selectedScope
        )
    }
}

private struct BlockingRuleEditRequest: Identifiable {
    let id = UUID()
    let keyword: String
    let scope: BlockingKeywordScope
}

private struct BlockingKeywordAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService

    let scope: BlockingKeywordScope
    var original: String? = nil

    @State private var keyword = ""
    @State private var feedback: BlockingKeywordFeedback?

    private var helpText: String {
        switch scope {
        case .common:
            "可直接输入关键词，也可使用 title:关键词、uploader:关键词、tag:关键词 限定匹配字段。"
        case .jmComic:
            "这里输入原始标签或关键词，JMComic 搜索时会自动使用 -关键词 排除。"
        }
    }

    var body: some View {
        PicaxNavigationContainer {
            Form {
                Section {
                    TextField("屏蔽关键词", text: $keyword)
                        .picaxDisablesTextAutocapitalization()
                        .autocorrectionDisabled()
                } footer: {
                    Text(helpText)
                }
            }
            .navigationTitle(original == nil ? "添加屏蔽词" : "编辑屏蔽词")
            .onAppear { keyword = original ?? "" }
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: addKeyword)
                }
            }
            .alert(item: $feedback) { feedback in
                Alert(
                    title: Text(feedback.title),
                    message: Text(feedback.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private func addKeyword() {
        let result = original.map { blockingKeywords.replace($0, with: keyword, scope: scope) }
            ?? blockingKeywords.add(keyword, scope: scope)
        if result.isSuccess {
            dismiss()
        } else {
            feedback = result
        }
    }
}
