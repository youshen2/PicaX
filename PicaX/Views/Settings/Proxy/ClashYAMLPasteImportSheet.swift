import SwiftUI

struct ClashYAMLPasteImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppProxySettings

    let onImported: (AppBuiltInProxyImportSummary) -> Void

    @State private var yaml = ""
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        PicaxNavigationContainer {
            Form {
                Section(
                    header: Text("Clash YAML"),
                    footer: Text(
                        "请粘贴包含 proxies: 列表的完整 YAML。内容只在本机解析。"
                    )
                ) {
                    TextEditor(text: $yaml)
                        .frame(minHeight: 220)
                        .font(.system(.caption, design: .monospaced))
                        .picaxDisablesTextAutocapitalization()
                        .disableAutocorrection(true)
                }

                if let errorMessage {
                    Section("无法导入") {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundColor(.red)
                    }
                }
            }
            .picaxHidesTabBar()
        .navigationTitle("粘贴 YAML")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await importNow() }
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("导入")
                        }
                    }
                    .disabled(
                        yaml.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty || isImporting
                    )
                }
            }
        }

    }

    private func importNow() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            let parsed = try await ClashYAMLImportWorker.parse(
                text: yaml
            )
            let summary = try settings.importBuiltInProxyParseResult(
                parsed
            )
            onImported(summary)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
