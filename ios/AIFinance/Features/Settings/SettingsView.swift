import AuthenticationServices
import CryptoKit
import FinanceCore
import SwiftUI
import UIKit

enum SettingsKeys {
    static let autoKeyboard = "autoKeyboard"
    static let voiceAutoSend = "voiceAutoSend"
    static let backupPromptShown = "backupPromptShown"
}

/// 設定（規格 7.7）。
struct SettingsView: View {
    @Environment(TimelineViewModel.self) private var model
    @Environment(CoachController.self) private var coach
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKeys.autoKeyboard) private var autoKeyboard = true
    @AppStorage(SettingsKeys.voiceAutoSend) private var voiceAutoSend = false

    @State private var profile = Profile()
    @State private var profileLoaded = false
    @State private var isLinked = false
    @State private var message: String?
    @State private var exportFile: ExportFile?
    @State private var isExporting = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var rawNonce = ""

    private static let thresholds = [1000, 3000, 5000, 10000]

    private var repository: TransactionRepository { model.transactionRepository }

    var body: some View {
        NavigationStack {
            Form {
                if model.isDemo {
                    Section {
                        Label("示範模式：還沒接上雲端，資料只存在這次開啟期間，解析也只是簡單規則。", systemImage: "flask")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Section {
                    Toggle("直接入帳", isOn: Binding(
                        get: { profile.autoCommit },
                        set: { profile.autoCommit = $0; saveProfile() }
                    ))
                    .accessibilityIdentifier("autoCommitToggle")
                    if profile.autoCommit {
                        Picker("金額門檻", selection: Binding(
                            get: { profile.autoCommitMax ?? 10000 },
                            set: { profile.autoCommitMax = $0; saveProfile() }
                        )) {
                            ForEach(Self.thresholds, id: \.self) { Text(Money.format($0)).tag($0) }
                        }
                    }
                } header: {
                    Text("記帳").textCase(nil)
                } footer: {
                    Text(profile.autoCommit
                        ? "金額在門檻以內、內容清楚的支出會直接記下來，記完可以復原。收入和超過門檻的會先讓你確認。"
                        : "每一筆都會先讓你確認再記。")
                }
                .disabled(!profileLoaded || !model.isOnline)

                Section {
                    Toggle("開啟時自動彈出鍵盤", isOn: $autoKeyboard)
                    Toggle("語音停止後自動送出", isOn: $voiceAutoSend)
                } header: {
                    Text("輸入").textCase(nil)
                }

                Section {
                    if isLinked {
                        Label("已綁定 Apple ID", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.income)
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            rawNonce = Self.randomNonce()
                            request.requestedScopes = []
                            request.nonce = Self.sha256(rawNonce)
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                        .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("備份").textCase(nil)
                } footer: {
                    Text(isLinked
                        ? "換手機或重裝後，用同一個 Apple ID 登入就能取回資料。"
                        : "現在資料只跟著這支手機。綁定之後，換手機或重裝都能取回。")
                }
                .disabled(!model.isOnline)

                Section {
                    Button {
                        export()
                    } label: {
                        HStack {
                            Text("匯出 CSV")
                            Spacer()
                            if isExporting { ProgressView() }
                        }
                    }
                    .disabled(isExporting)
                    .accessibilityIdentifier("exportButton")

                    Button("刪除所有資料", role: .destructive) { confirmDelete = true }
                        .disabled(isDeleting)
                        .accessibilityIdentifier("deleteAllButton")
                } header: {
                    Text("資料").textCase(nil)
                }
                .disabled(!model.isOnline)

                if let message {
                    Section {
                        Text(message).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }

                Section {
                    // 設定頁收起來之後，主畫面會重新跑一次聚光燈引導。
                    Button("重看教學") {
                        coach.requestReplay()
                        dismiss()
                    }
                    .accessibilityIdentifier("replayCoach")
                    NavigationLink("隱私說明") { PrivacyView() }
                    LabeledContent("版本", value: Self.version)
                } header: {
                    Text("關於").textCase(nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("刪除所有資料？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("全部刪除", role: .destructive) { deleteAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有紀錄、原話和分類習慣都會從雲端與這支手機刪除，刪了就救不回來。需要的話請先匯出 CSV。")
            }
            .sheet(item: $exportFile) { file in
                ActivityView(url: file.url)
            }
        }
        .tint(Theme.accent)
        .task {
            isLinked = await repository.isLinked
            if let loaded = try? await repository.profile() {
                profile = loaded
                profileLoaded = true
            }
        }
    }

    // MARK: - 動作

    private func saveProfile() {
        let snapshot = profile
        Task {
            do {
                try await repository.updateProfile(snapshot)
                message = nil
            } catch {
                message = "設定沒有存成功，請稍後再試。"
            }
        }
    }

    private func export() {
        isExporting = true
        message = nil
        Task {
            do {
                exportFile = ExportFile(url: try await repository.exportCSV())
            } catch {
                message = "匯出失敗，請稍後再試。"
            }
            isExporting = false
        }
    }

    private func deleteAll() {
        isDeleting = true
        Task {
            do {
                try await repository.deleteAll()
                model.resetAfterWipe()
                profile = Profile()
                message = "所有資料都刪除了。"
            } catch {
                message = "刪除失敗，資料還在。請稍後再試。"
            }
            isDeleting = false
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            // 使用者自己取消不算錯誤。
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code == .canceled { return }
            message = "Apple 登入沒有完成，請再試一次。"
            return
        }
        let nonce = rawNonce
        // 手機上已經有紀錄時，不直接換成舊帳號，免得這些紀錄看起來像不見了。
        let allowSwitch = !model.hasLocalData
        Task {
            do {
                let switched = try await repository.linkApple(idToken: idToken, rawNonce: nonce, allowSwitch: allowSwitch)
                isLinked = true
                if switched {
                    await model.reloadAfterAccountSwitch()
                    if let loaded = try? await repository.profile() { profile = loaded }
                    message = "已經取回這個 Apple ID 的資料。"
                } else {
                    message = "綁定完成。"
                }
            } catch BackendError.server(let code, _) where code == "apple_already_linked" {
                message = "這個 Apple ID 已經有一份備份了，但這支手機上還有新記的紀錄。想換回那份備份的話，先匯出 CSV，再刪除所有資料，然後重新按一次。"
            } catch let error as BackendError {
                message = error.message
            } catch {
                message = "綁定沒有成功，請稍後再試。"
            }
        }
    }

    // MARK: - 工具

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
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

/// 隱私說明：哪些內容會傳給 AI 服務（規格 7.7、第 10 節）。
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                block("會傳給 AI 服務的內容", [
                    "你輸入或講的那一句話（原話）。",
                    "分類清單，以及你改過分類後留下的習慣（例如「麥當勞→飲食」）。",
                    "你提問時，查詢出來的統計結果（總額、筆數、明細）。",
                ])
                block("不會傳給 AI 服務的內容", [
                    "你的帳號、Apple ID、裝置識別碼。",
                    "跟這次輸入無關的其他紀錄。",
                ])
                block("語音", [
                    "語音由 Apple 的語音辨識轉成文字，App 不保存錄音。轉出來的文字跟打字的一樣處理。",
                ])
                block("資料存在哪裡", [
                    "紀錄存在雲端資料庫，只有你的帳號讀得到。手機上另外留一份方便離線查看。",
                    "金額、統計全部由資料庫計算，AI 只負責看懂你的話和解釋結果。",
                ])
                block("你可以做的事", [
                    "在設定匯出全部紀錄（CSV）。",
                    "在設定刪除所有資料，雲端與手機上的都會刪掉。",
                ])
            }
            .padding(Theme.spacing(2))
        }
        .background(Theme.background)
        .navigationTitle("隱私說明")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
