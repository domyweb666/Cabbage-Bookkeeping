import FinanceCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(LedgerModel.self) private var model

    @State private var exportFile: ExportFile?
    @State private var alertText: String?
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("匯出資料") { export() }
                        .disabled(model.isEmpty)
                        .accessibilityIdentifier("exportButton")
                    Button("清除所有資料", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("deleteAllButton")
                } header: {
                    Text("資料").textCase(nil)
                }

                Section {
                    NavigationLink("隱私說明") { PrivacyView() }
                    LabeledContent("版本", value: Self.version)
                } header: {
                    Text("關於").textCase(nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("設定")
            // 問兩次，兩次的按鈕字不同；第一次附「先匯出」。
            .alert("清除所有資料？", isPresented: $confirmDelete) {
                Button("先匯出") { export() }
                Button("繼續", role: .destructive) { confirmDeleteAgain = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有紀錄和預算都會從這支手機刪除，刪了就救不回來。")
            }
            .alert("真的要全部刪除？", isPresented: $confirmDeleteAgain) {
                Button("全部刪除", role: .destructive) {
                    alertText = model.deleteAll() ? "所有資料都刪除了。" : "刪除失敗，資料還在。"
                }
                Button("取消", role: .cancel) {}
            }
            .alert(alertText ?? "", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button("好", role: .cancel) {}
            }
            .sheet(item: $exportFile) { ActivityView(url: $0.url) }
        }
        .tint(Theme.accent)
    }

    private func export() {
        do {
            exportFile = ExportFile(url: try model.exportCSV())
        } catch {
            alertText = "匯出失敗，手機空間可能不夠。"
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// 系統的分享面板。
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PrivacyView: View {
    private static let lines = [
        "紀錄和預算都存在這支手機上，不會上傳，App 也不連網路。",
        "分析頁的數字全部在手機上算。",
        "手機有開 iCloud 備份的話，紀錄會跟著整支手機一起備份。",
        "設定裡可以匯出全部紀錄，也可以全部刪除。把 App 刪掉，紀錄也會跟著刪掉。",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Gap.group) {
                ForEach(Self.lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(Theme.Gap.screen)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("隱私說明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
