import SwiftUI

struct DownloadIntegritySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloads: DownloadService
    let record: DownloadRecord
    @State private var report: DownloadIntegrityReport?
    @State private var message: String?
    @State private var progress = "正在检查页面"
    @State private var isWorking = true
    @State private var repairTask: Task<Void, Never>?

    var body: some View {
        PicaxNavigationContainer {
            List {
                if isWorking { HStack { ProgressView(); Text(progress) } }
                if let message { Text(message).foregroundStyle(.red) }
                if let report {
                    Section("检查结果") {
                        Text("已检查 \(report.checkedPages) 页，发现 \(report.issues.count) 页缺失或损坏")
                        if !report.issues.isEmpty {
                            if record.item.platform == .local {
                                Text("请从原始文件重新导入，以恢复损坏页面。").foregroundStyle(.secondary)
                            } else {
                                Button("仅修复有问题的页面") { repair() }.disabled(isWorking)
                            }
                        }
                    }
                    ForEach(record.chapters) { chapter in
                        let issues = report.issues.filter { $0.chapterIndex == chapter.index }
                        if !issues.isEmpty {
                            Section(chapter.chapter.title) {
                                ForEach(issues) { issue in Text("第 \(issue.pageIndex + 1) 页") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("完整性检查")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isWorking ? "取消" : "完成") { repairTask?.cancel(); dismiss() }
                }
            }
        }
        .task { await inspect() }
        .onDisappear { repairTask?.cancel() }
    }

    private func inspect() async {
        do { report = try await downloads.inspectIntegrity(of: record) }
        catch { if !error.isTaskCancellation { message = error.localizedDescription } }
        isWorking = false
    }

    private func repair() {
        guard let report else { return }
        isWorking = true
        message = nil
        progress = "正在修复"
        repairTask = Task {
            do {
                try await downloads.repair(report, record: record) { done, total in progress = "已修复 \(done)/\(total) 页" }
                self.report = DownloadIntegrityReport(recordID: report.recordID, checkedPages: report.checkedPages, issues: [])
                isWorking = false
            } catch {
                if !error.isTaskCancellation { message = error.localizedDescription }
                isWorking = false
            }
        }
    }
}
