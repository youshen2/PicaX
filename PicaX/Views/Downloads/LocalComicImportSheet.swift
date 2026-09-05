import SwiftUI
import UniformTypeIdentifiers

struct LocalComicImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloads: DownloadService
    @AppStorage(LocalComicImportSettings.pdfPageWidth) private var pdfWidth = 1800
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var progress = ""
    @State private var feedback: [String] = []
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        PicaxNavigationContainer {
            Form {
                Section {
                    Picker("PDF 页面宽度", selection: $pdfWidth) {
                        Text("1200 像素").tag(1200)
                        Text("1800 像素").tag(1800)
                        Text("2400 像素").tag(2400)
                        Text("3000 像素").tag(3000)
                    }
                    .disabled(isImporting)
                    Button("选择 ZIP、CBZ 或 PDF") { showsImporter = true }.disabled(isImporting)
                } footer: {
                    Text("图片按文件名自然排序导入，PDF 会转换为阅读页面。导入后可在离线书库阅读、添加书签并记录进度；更高的 PDF 分辨率会占用更多空间。")
                }
                if isImporting { HStack { ProgressView(); Text(progress) } }
                ForEach(Array(feedback.enumerated()), id: \.offset) { _, message in Text(message) }
            }
            .navigationTitle("本地漫画导入")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "取消" : "完成") { importTask?.cancel(); dismiss() }
                }
            }
            .fileImporter(isPresented: $showsImporter,
                          allowedContentTypes: [.zip, .pdf, UTType(importedAs: "moye.picax.cbz", conformingTo: .zip)],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    isImporting = true
                    feedback = []
                    importTask = Task {
                        for (index, url) in urls.enumerated() {
                            guard !Task.isCancelled else { break }
                            progress = "\(index + 1)/\(urls.count) · \(url.lastPathComponent)"
                            do {
                                try await downloads.importComic(from: url)
                                feedback.append("已导入：\(url.lastPathComponent)")
                            } catch {
                                if !error.isTaskCancellation { feedback.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
                            }
                        }
                        isImporting = false
                    }
                case .failure(let error): feedback = [error.localizedDescription]
                }
            }
        }
        .onDisappear { importTask?.cancel() }
    }
}
