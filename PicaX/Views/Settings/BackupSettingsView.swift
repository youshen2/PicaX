import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct BackupSettingsView: View {
    @State private var selectedBackupContent = BackupContentKind.defaultSelection
    @State private var isPreparingExport = false
    @State private var isPreparingImport = false
    @State private var isImporting = false
    @State private var exportDocument = PicaXBackupDocument()
    @State private var exportTemporaryFileURL: URL?
    @State private var exportFileName = "PicaX-Backup"
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var activeImportSource = BackupImportSource.picax
    @State private var pendingImport: BackupImportPreview?
    @State private var operationResult: BackupOperationResult?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WebDAVSettingsView()
                } label: {
                    Label(
                        "WebDAV 备份与同步",
                        systemImage: "externaldrive.connected.to.line.below"
                    )
                }
            } footer: {
                Text("通过支持 WebDAV 的服务器在设备间合并同步数据，或保留独立的远端备份。")
            }

            Section {
                ForEach(BackupContentKind.allCases) { content in
                    Toggle(content.title, isOn: backupContentBinding(for: content))
                }
            } header: {
                Text("导出内容")
            } footer: {
                Text("选择要放进备份的内容。账号资料不包含密码、令牌或 Cookie；已下载漫画包含下载记录和本地文件。未选择的内容不会导出，也不会在覆盖导入时被清空。")
            }

            Section {
                Button {
                    Task {
                        await prepareExport()
                    }
                } label: {
                    if isPreparingExport {
                        HStack {
                            ProgressView()
                            Text("正在准备备份")
                        }
                    } else {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingExport || isPreparingImport || isImporting || selectedBackupContent.isEmpty)
            } footer: {
                Text(selectedBackupContent.isEmpty ? "至少选择一项内容后才能导出。" : "备份文件会保存为 .picax。")
            }

            Section {
                Button {
                    activeImportSource = .picaComic
                    showsImporter = true
                } label: {
                    if isPreparingImport, activeImportSource == .picaComic {
                        HStack {
                            ProgressView()
                            Text("正在读取 PicaComic 备份")
                        }
                    } else {
                        Label("从 PicaComic 备份导入", systemImage: "tray.and.arrow.down")
                    }
                }
                .disabled(isPreparingExport || isPreparingImport || isImporting)

                Button {
                    activeImportSource = .picax
                    showsImporter = true
                } label: {
                    if isPreparingImport, activeImportSource == .picax {
                        HStack {
                            ProgressView()
                            Text("正在读取备份")
                        }
                    } else if isImporting {
                        HStack {
                            ProgressView()
                            Text("正在导入")
                        }
                    } else {
                        Label("导入备份", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isPreparingExport || isPreparingImport || isImporting)
            } footer: {
                Text("导入时可以选择完全覆盖或合并本地数据。合并会保留本地已有设置，并合并历史、收藏、账号、屏蔽词和下载记录。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("备份与恢复")
        .picaxHidesTabBar()
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .picaxBackup,
            defaultFilename: exportFileName
        ) { result in
            if let exportTemporaryFileURL {
                try? FileManager.default.removeItem(at: exportTemporaryFileURL)
                self.exportTemporaryFileURL = nil
            }
            switch result {
            case .success:
                operationResult = BackupOperationResult(title: "导出完成", message: "备份文件已保存。")
            case .failure(let error):
                operationResult = BackupOperationResult(title: "导出失败", message: error.localizedDescription)
            }
        }
        .backupDocumentImporter(
            isPresented: $showsImporter,
            allowedContentTypes: activeImportSource.allowedContentTypes
        ) { result in
            handleImporterResult(result)
        }
        .sheet(item: $pendingImport) { preview in
            BackupImportPreviewSheet(
                preview: preview,
                isImporting: isImporting,
                onCancel: {
                    pendingImport = nil
                },
                onOverwrite: { includedContent in
                    Task {
                        await importBackup(preview, mode: .overwrite, includedContent: includedContent)
                    }
                },
                onMerge: { includedContent in
                    Task {
                        await importBackup(preview, mode: .merge, includedContent: includedContent)
                    }
                }
            )
        }
        .alert(item: $operationResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func backupContentBinding(for content: BackupContentKind) -> Binding<Bool> {
        Binding {
            selectedBackupContent.contains(content)
        } set: { isSelected in
            if isSelected {
                selectedBackupContent.insert(content)
            } else {
                selectedBackupContent.remove(content)
            }
        }
    }

    @MainActor
    private func prepareExport() async {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }

        do {
            let document = try await BackupService.makeDocument(includedContent: selectedBackupContent)
            if let exportTemporaryFileURL {
                try? FileManager.default.removeItem(at: exportTemporaryFileURL)
            }
            exportDocument = document
            exportTemporaryFileURL = document.temporaryFileURL
            exportFileName = "PicaX-Backup-\(Self.fileNameFormatter.string(from: Date())).picax"
            showsExporter = true
        } catch {
            operationResult = BackupOperationResult(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func handleImporterResult(_ result: Result<[URL], Error>) {
        let source = activeImportSource

        do {
            guard let url = try result.get().first else { return }
            guard source.accepts(url) else {
                operationResult = BackupOperationResult(title: source.failureTitle, message: source.invalidFileMessage)
                return
            }
            Task {
                await loadBackupPreview(from: url, source: source)
            }
        } catch {
            operationResult = BackupOperationResult(title: source.failureTitle, message: error.localizedDescription)
        }
    }

    @MainActor
    private func loadBackupPreview(from url: URL, source: BackupImportSource) async {
        guard !isPreparingImport else { return }
        isPreparingImport = true
        defer { isPreparingImport = false }

        do {
            let data = try await Self.readSecurityScopedData(from: url)
            pendingImport = try source.preview(from: data)
        } catch {
            operationResult = BackupOperationResult(title: source.failureTitle, message: error.localizedDescription)
        }
    }

    private static func readSecurityScopedData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try Data(contentsOf: url)
        }.value
    }

    @MainActor
    private func importBackup(_ preview: BackupImportPreview, mode: BackupImportMode, includedContent: Set<BackupContentKind>) async {
        guard !isImporting else { return }
        isImporting = true
        defer {
            isImporting = false
            self.pendingImport = nil
        }

        do {
            let filtered = BackupService.filteredBackup(
                preview.backup,
                includedContent: includedContent
            )
            try await BackupService.importBackup(
                filtered,
                mode: mode,
                archiveData: preview.data
            )
            operationResult = BackupOperationResult(title: "导入完成", message: mode == .overwrite ? "备份已覆盖本地数据。" : "备份已与本地数据合并。")
        } catch {
            operationResult = BackupOperationResult(title: "导入失败", message: error.localizedDescription)
        }
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct WebDAVSettingsView: View {
    @EnvironmentObject private var webDAVSync: WebDAVSyncService

    @AppStorage(WebDAVSettingsKey.automaticSyncEnabled) private var automaticSyncEnabled = false
    @AppStorage(WebDAVSettingsKey.syncContentSelection) private var syncContentSelectionRaw = WebDAVSyncContentSettings.defaultRawValue
    @AppStorage(WebDAVSettingsKey.lastSuccessfulSyncAt) private var lastSuccessfulSyncTimestamp = 0.0

    @State private var serverURL: String
    @State private var username: String
    @State private var password: String
    @State private var remoteDirectory: String
    @State private var hasLoadedBackups = false
    @State private var isImporting = false
    @State private var pendingImport: BackupImportPreview?
    @State private var pendingDelete: WebDAVRemoteBackup?
    @State private var operationResult: BackupOperationResult?

    init() {
        let configuration = try? WebDAVConfigurationStore.load()
        _serverURL = State(initialValue: configuration?.displayServerURL ?? "")
        _username = State(initialValue: configuration?.username ?? "")
        _password = State(initialValue: configuration?.password ?? "")
        _remoteDirectory = State(initialValue: configuration?.remoteDirectory ?? WebDAVSettingsKey.defaultRemoteDirectory)
    }

    var body: some View {
        List {
            configurationSection
            syncSection
            remoteBackupsSection
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("WebDAV")
        .picaxHidesTabBar()
        .task {
            guard !serverURL.isEmpty, !webDAVSync.isBusy else { return }
            await refreshBackups(showsSuccess: false)
        }
        .sheet(item: $pendingImport) { preview in
            BackupImportPreviewSheet(
                preview: preview,
                isImporting: isImporting,
                onCancel: { pendingImport = nil },
                onOverwrite: { includedContent in
                    Task {
                        await importRemoteBackup(preview, mode: .overwrite, includedContent: includedContent)
                    }
                },
                onMerge: { includedContent in
                    Task {
                        await importRemoteBackup(preview, mode: .merge, includedContent: includedContent)
                    }
                }
            )
        }
        .alert(item: $operationResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("好"))
            )
        }
        .confirmationDialog(
            "删除远端备份？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { backup in
            Button("删除 \(backup.name)", role: .destructive) {
                Task { await deleteBackup(backup) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除后无法从 WebDAV 恢复此备份。")
        }
    }

    private var configurationSection: some View {
        Section {
            TextField("https://example.com/webdav/", text: $serverURL)
                .picaxKeyboardType(.url)
                .picaxDisablesTextAutocapitalization()
                .autocorrectionDisabled()
            TextField("用户名", text: $username)
                .picaxDisablesTextAutocapitalization()
                .autocorrectionDisabled()
            SecureField("密码或应用专用密码", text: $password)
            TextField("远端目录", text: $remoteDirectory)
                .picaxDisablesTextAutocapitalization()
                .autocorrectionDisabled()

            Button {
                Task { await saveAndTest() }
            } label: {
                activityLabel(defaultTitle: "保存并测试连接", systemImage: "checkmark.icloud", activity: .testing)
            }
            .disabled(isBusy || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("服务器")
        } footer: {
            Text("请输入 WebDAV 根地址。用户名和服务器地址保存在本机设置中，密码仅保存在 Keychain。建议使用 HTTPS。")
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("App 激活时自动同步", isOn: $automaticSyncEnabled)

            ForEach(BackupContentKind.allCases) { content in
                Toggle(content.title, isOn: syncContentBinding(for: content))
                .disabled(isBusy)
            }

            Button {
                Task { await synchronize() }
            } label: {
                activityLabel(defaultTitle: "立即同步", systemImage: "arrow.triangle.2.circlepath.icloud", activity: .syncing)
            }
            .disabled(isBusy || syncContentSelection.isEmpty)

            Button {
                Task { await createRemoteBackup() }
            } label: {
                activityLabel(defaultTitle: "备份到 WebDAV", systemImage: "icloud.and.arrow.up", activity: .backingUp)
            }
            .disabled(isBusy || syncContentSelection.isEmpty)

            if lastSuccessfulSyncTimestamp > 0 {
                LabeledContent("上次同步", value: Self.dateFormatter.string(from: lastSuccessfulSyncAt))
                    .foregroundStyle(.secondary)
            }

        } header: {
            Text("同步内容")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error = webDAVSync.lastAutomaticSyncError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text(syncContentSelection.isEmpty
                    ? "至少选择一项内容后才能备份或同步。"
                    : "同步会先合并服务器上的 PicaX-Sync.picax，再上传合并后的数据。已下载漫画可能产生较大流量。")
            }
        }
    }

    private var remoteBackupsSection: some View {
        Section {
            Button {
                Task { await refreshBackups(showsSuccess: true) }
            } label: {
                activityLabel(defaultTitle: "刷新远端备份", systemImage: "arrow.clockwise", activity: .loading)
            }
            .disabled(isBusy)

            ForEach(webDAVSync.backups) { backup in
                Button {
                    Task { await downloadBackup(backup) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.zipper")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(backup.name)
                                .foregroundStyle(.primary)
                            Text(remoteBackupDetail(backup))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if webDAVSync.activity == .downloading(backup.name) {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .swipeActions {
                    Button(role: .destructive) {
                        pendingDelete = backup
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }

            if hasLoadedBackups, webDAVSync.backups.isEmpty {
                ContentUnavailableView(
                    "没有远端备份",
                    systemImage: "icloud",
                    description: Text("点击“备份到 WebDAV”创建第一份备份。")
                )
            }
        } header: {
            Text("远端备份")
        } footer: {
            Text("这里显示独立的时间戳备份；设备间自动同步使用的固定文件不会列出。点击备份可预览并选择合并或覆盖恢复。")
        }
    }

    private var syncContentSelection: Set<BackupContentKind> {
        WebDAVSyncContentSettings.selection(from: syncContentSelectionRaw)
    }

    private var isBusy: Bool {
        webDAVSync.isBusy || isImporting
    }

    private var lastSuccessfulSyncAt: Date {
        Date(timeIntervalSince1970: lastSuccessfulSyncTimestamp)
    }

    private func syncContentBinding(for content: BackupContentKind) -> Binding<Bool> {
        Binding {
            syncContentSelection.contains(content)
        } set: { isSelected in
            var selection = syncContentSelection
            if isSelected {
                selection.insert(content)
            } else {
                selection.remove(content)
            }
            syncContentSelectionRaw = WebDAVSyncContentSettings.rawValue(for: selection)
        }
    }

    @ViewBuilder
    private func activityLabel(defaultTitle: String, systemImage: String, activity: WebDAVSyncService.Activity) -> some View {
        if webDAVSync.activity == activity {
            HStack {
                ProgressView()
                Text(activity.title ?? defaultTitle)
            }
        } else {
            Label(defaultTitle, systemImage: systemImage)
        }
    }

    @MainActor
    private func saveAndTest() async {
        do {
            let configuration = try saveConfiguration()
            try await webDAVSync.test(configuration: configuration)
            try await webDAVSync.refresh(configuration: configuration)
            hasLoadedBackups = true
            operationResult = BackupOperationResult(title: "连接成功", message: "WebDAV 配置已保存，远端目录可以访问。")
        } catch {
            operationResult = BackupOperationResult(title: "连接失败", message: error.localizedDescription)
        }
    }

    @MainActor
    private func refreshBackups(showsSuccess: Bool) async {
        do {
            let configuration = try saveConfiguration()
            try await webDAVSync.refresh(configuration: configuration)
            hasLoadedBackups = true
            if showsSuccess {
                operationResult = BackupOperationResult(title: "刷新完成", message: "已读取 \(webDAVSync.backups.count) 份远端备份。")
            }
        } catch {
            operationResult = BackupOperationResult(title: "刷新失败", message: error.localizedDescription)
        }
    }

    @MainActor
    private func createRemoteBackup() async {
        do {
            let configuration = try saveConfiguration()
            let fileName = try await webDAVSync.createBackup(
                configuration: configuration,
                includedContent: syncContentSelection
            )
            hasLoadedBackups = true
            operationResult = BackupOperationResult(title: "备份完成", message: "已上传 \(fileName)。")
        } catch {
            operationResult = BackupOperationResult(title: "备份失败", message: error.localizedDescription)
        }
    }

    @MainActor
    private func synchronize() async {
        do {
            let configuration = try saveConfiguration()
            try await webDAVSync.synchronize(
                configuration: configuration,
                includedContent: syncContentSelection
            )
            hasLoadedBackups = true
            operationResult = BackupOperationResult(title: "同步完成", message: "远端与本地数据已合并，并已上传最新同步副本。")
        } catch {
            operationResult = BackupOperationResult(title: "同步失败", message: error.localizedDescription)
        }
    }

    @MainActor
    private func downloadBackup(_ backup: WebDAVRemoteBackup) async {
        do {
            let configuration = try saveConfiguration()
            pendingImport = try await webDAVSync.download(backup, configuration: configuration)
        } catch {
            operationResult = BackupOperationResult(title: "下载失败", message: error.localizedDescription)
        }
    }

    @MainActor
    private func deleteBackup(_ backup: WebDAVRemoteBackup) async {
        pendingDelete = nil
        do {
            let configuration = try saveConfiguration()
            try await webDAVSync.delete(backup, configuration: configuration)
            operationResult = BackupOperationResult(title: "删除完成", message: "远端备份已删除。")
        } catch {
            operationResult = BackupOperationResult(title: "删除失败", message: error.localizedDescription)
        }
    }

    @MainActor
    private func importRemoteBackup(
        _ preview: BackupImportPreview,
        mode: BackupImportMode,
        includedContent: Set<BackupContentKind>
    ) async {
        guard !isImporting else { return }
        isImporting = true
        defer {
            isImporting = false
            pendingImport = nil
        }
        do {
            let filtered = BackupService.filteredBackup(
                preview.backup,
                includedContent: includedContent
            )
            try await BackupService.importBackup(
                filtered,
                mode: mode,
                archiveData: preview.data
            )
            operationResult = BackupOperationResult(
                title: "恢复完成",
                message: mode == .overwrite ? "远端备份已覆盖所选本地数据。" : "远端备份已与本地数据合并。"
            )
        } catch {
            operationResult = BackupOperationResult(title: "恢复失败", message: error.localizedDescription)
        }
    }

    private func saveConfiguration() throws -> WebDAVConfiguration {
        let configuration = try WebDAVConfigurationStore.save(
            serverURL: serverURL,
            username: username,
            password: password,
            remoteDirectory: remoteDirectory
        )
        serverURL = configuration.displayServerURL
        username = configuration.username
        remoteDirectory = configuration.remoteDirectory
        return configuration
    }

    private func remoteBackupDetail(_ backup: WebDAVRemoteBackup) -> String {
        var values: [String] = []
        if let modifiedAt = backup.modifiedAt {
            values.append(Self.dateFormatter.string(from: modifiedAt))
        }
        if let size = backup.size {
            values.append(Self.byteFormatter.string(fromByteCount: size))
        }
        return values.isEmpty ? "远端备份" : values.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private enum BackupImportSource {
    case picax
    case picaComic

    var allowedContentTypes: [UTType] {
        switch self {
        case .picax:
            [.picaxBackup]
        case .picaComic:
            [.picaComicBackup]
        }
    }

    var expectedFileExtension: String {
        switch self {
        case .picax:
            "picax"
        case .picaComic:
            "picadata"
        }
    }

    var invalidFileMessage: String {
        switch self {
        case .picax:
            "请选择 .picax 备份文件。"
        case .picaComic:
            "请选择 .picadata 备份文件。"
        }
    }

    var failureTitle: String {
        switch self {
        case .picax:
            "读取备份失败"
        case .picaComic:
            "读取 PicaComic 备份失败"
        }
    }

    func accepts(_ url: URL) -> Bool {
        url.pathExtension.compare(expectedFileExtension, options: [.caseInsensitive]) == .orderedSame
    }

    func preview(from data: Data) throws -> BackupImportPreview {
        switch self {
        case .picax:
            try BackupService.preview(from: data)
        case .picaComic:
            try PicaComicBackupImporter.preview(from: data)
        }
    }
}

private extension View {
    @ViewBuilder
    func backupDocumentImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
#if os(iOS)
        sheet(isPresented: isPresented) {
            BackupDocumentPicker(allowedContentTypes: allowedContentTypes) { result in
                isPresented.wrappedValue = false
                onCompletion(result)
            }
        }
#else
        fileImporter(
            isPresented: isPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: onCompletion
        )
#endif
    }
}

#if os(iOS)
private struct BackupDocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onCompletion: (Result<[URL], Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<[URL], Error>) -> Void

        init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.success([]))
        }
    }
}
#endif

private struct BackupImportPreviewSheet: View {
    let preview: BackupImportPreview
    let isImporting: Bool
    let onCancel: () -> Void
    let onOverwrite: (Set<BackupContentKind>) -> Void
    let onMerge: (Set<BackupContentKind>) -> Void
    @State private var selectedContent: Set<BackupContentKind>
    @State private var showsOverwriteConfirmation = false

    init(
        preview: BackupImportPreview,
        isImporting: Bool,
        onCancel: @escaping () -> Void,
        onOverwrite: @escaping (Set<BackupContentKind>) -> Void,
        onMerge: @escaping (Set<BackupContentKind>) -> Void
    ) {
        self.preview = preview
        self.isImporting = isImporting
        self.onCancel = onCancel
        self.onOverwrite = onOverwrite
        self.onMerge = onMerge
        _selectedContent = State(initialValue: preview.backup.contentSelection)
    }

    private var includedContent: [BackupContentKind] {
        BackupContentKind.allCases.filter { preview.backup.contentSelection.contains($0) }
    }

    private var canImport: Bool {
        !isImporting && !selectedContent.isEmpty
    }

    var body: some View {
        PicaxNavigationContainer {
            List {
                Section {
                    LabeledContent("来源", value: preview.title)
                    LabeledContent("创建时间", value: Self.dateFormatter.string(from: preview.backup.createdAt))
                    LabeledContent("本地数据", value: "\(preview.backup.defaults.count) 项")
                    LabeledContent("漫画文件", value: "\(preview.backup.downloadFiles.count) 个")
                }

                Section {
                    HStack {
                        Button("全选") {
                            selectedContent = Set(includedContent)
                        }
                        .disabled(isImporting || selectedContent.count == includedContent.count)

                        Spacer()

                        Button("清空") {
                            selectedContent.removeAll()
                        }
                        .disabled(isImporting || selectedContent.isEmpty)
                    }

                    ForEach(includedContent) { content in
                        Toggle(content.title, isOn: importContentBinding(for: content))
                        .disabled(isImporting)
                    }
                } header: {
                    Text("导入内容")
                } footer: {
                    Text(selectedContent.isEmpty ? "至少选择一项内容后才能导入。" : "默认全选；关闭的内容不会被导入，覆盖本地时也不会清空对应本地数据。")
                }

                Section {
                    Button {
                        onMerge(selectedContent)
                    } label: {
                        if isImporting {
                            HStack {
                                ProgressView()
                                Text("正在导入")
                            }
                        } else {
                            Label("合并导入", systemImage: "plus.circle")
                        }
                    }
                    .disabled(!canImport)

                    Button(role: .destructive) {
                        showsOverwriteConfirmation = true
                    } label: {
                        Label("覆盖本地", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!canImport)
                } footer: {
                    Text("合并会保留本地已有内容；覆盖只会替换所选内容。")
                }
            }
            .navigationTitle(preview.title)
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                    .disabled(isImporting)
                }
            }
        }
        .picaxPresentationDetents([.medium, .large], showsDragIndicator: false)
        .alert("覆盖所选本地数据？", isPresented: $showsOverwriteConfirmation) {
            Button("覆盖本地", role: .destructive) {
                onOverwrite(selectedContent)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选类别的本地数据会被备份内容替换；未选择的类别不会改变。")
        }
    }

    private func importContentBinding(for content: BackupContentKind) -> Binding<Bool> {
        Binding {
            selectedContent.contains(content)
        } set: { isSelected in
            if isSelected {
                selectedContent.insert(content)
            } else {
                selectedContent.remove(content)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
