import FinanceCore
import SwiftUI
import UIKit
import VeggieKit

/// 設定頁照蔬菜家族的順序：app 專屬 → 一般 → 資料 →（購買、支援還沒有）→ 關於 → 頁尾。
/// 只放現在真的能用的列。意見回饋、評分、分享、隱私權政策等 Veggie.swift 填了值再加。
struct SettingsView: View {
    @Environment(LedgerModel.self) private var model
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(VeggieHaptics.storageKey) private var haptics = true

    @State private var exportFile: ExportFile?
    @State private var alertText: String?
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false

    private let config = VeggieConfig.baicai

    /// 匯出的是全部帳本的，所以看全部帳本有沒有紀錄。
    private var canExport: Bool { model.hasAnyRecord && !model.loadFailed }

    var body: some View {
        NavigationStack {
            DomyPage(title: Words.Settings.title, background: Theme.background, bottomInset: 0) {
                appSection
                generalSection
                dataSection
                aboutSection
                VeggieFooter(config: config, logo: Image("AppLogo")) { model.notice($0) }
                    .buttonStyle(.plain)
            }
            .coversStatusBar()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                ToastSlot().padding(.horizontal, Gap.screenMargin)
            }
            // 問兩次，兩次的按鈕字不同；第一次附「先匯出」。讀不出來時匯出會是空的，就不附。
            .alert(Words.Settings.eraseTitle, isPresented: $confirmDelete) {
                if !model.loadFailed {
                    Button(Words.Settings.exportFirst) { export() }
                }
                Button(Words.Settings.eraseContinue, role: .destructive) { confirmDeleteAgain = true }
                Button(Words.cancel, role: .cancel) {}
            } message: {
                Text(Words.Settings.eraseMessage)
            }
            .alert(Words.Settings.eraseAgainTitle, isPresented: $confirmDeleteAgain) {
                Button(Words.Settings.eraseConfirm, role: .destructive) {
                    alertText = model.deleteAll() ? Words.Settings.erased : Words.Failure.eraseAll
                }
                Button(Words.cancel, role: .cancel) {}
            }
            .alert(alertText ?? "", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button(Words.ok, role: .cancel) {}
            }
            .sheet(item: $exportFile) { ActivityView(url: $0.url) }
        }
        .veggieStyle(.baicai)
        .tint(Theme.accent)
    }

    private var appSection: some View {
        RowCard(Words.Settings.appSection) {
            // 帳本放第一列（K6）：右邊寫現在這本，點進去換、新增、改名字、刪除。
            NavigationLink {
                LedgerListView()
            } label: {
                VeggieRow(
                    icon: "book.closed", title: Words.Ledgers.title, value: model.currentLedger.name, accessory: .push
                )
            }
            .buttonStyle(.row)
            .accessibilityIdentifier("ledgersRow")
            RowDivider()
            NavigationLink {
                CategoryPickerView(showsDone: false)
            } label: {
                VeggieRow(icon: "square.grid.2x2", title: Words.Categories.title, accessory: .push)
            }
            .buttonStyle(.row)
            .accessibilityIdentifier("categoriesRow")
            RowDivider()
            NavigationLink {
                FixedListView()
            } label: {
                VeggieRow(icon: "calendar.badge.clock", title: Words.Fixed.title, accessory: .push)
            }
            .buttonStyle(.row)
            .accessibilityIdentifier("fixedRow")
            RowDivider()
            NavigationLink {
                SavingsPage()
            } label: {
                VeggieRow(
                    icon: "banknote", title: Words.Saving.title,
                    value: Words.Saving.settingsValue(model.savings, today: model.today), accessory: .push
                )
            }
            .buttonStyle(.row)
            .accessibilityIdentifier("savingsRow")
        }
    }

    private var generalSection: some View {
        RowCard(VeggieText.general) {
            Menu {
                Picker(VeggieText.appearance, selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                VeggieRow(icon: "circle.lefthalf.filled", title: VeggieText.appearance, value: appearance.title)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("appearanceRow")
            .onChange(of: appearance) { _, value in
                value.apply()
            }
            RowDivider()
            VeggieToggleRow(icon: "iphone.radiowaves.left.and.right", title: VeggieText.haptics, isOn: $haptics)
        }
    }

    private var dataSection: some View {
        RowCard(VeggieText.data) {
            Button {
                export()
            } label: {
                VeggieRow(icon: "square.and.arrow.up", title: VeggieText.exportData)
                    .opacity(canExport ? 1 : Motion.pressOpacity / 2)
            }
            .buttonStyle(.row)
            .disabled(!canExport)
            .accessibilityIdentifier("exportButton")
            RowDivider()
            Button {
                confirmDelete = true
            } label: {
                VeggieRow(icon: "trash", title: VeggieText.eraseAll, destructive: true)
            }
            .buttonStyle(.row)
            .accessibilityIdentifier("deleteAllButton")
        }
    }

    private var aboutSection: some View {
        RowCard(VeggieText.about) {
            if !VeggieApp.others(excluding: config.slug).isEmpty {
                NavigationLink {
                    VeggieFamilyView(config: config)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    VeggieRow(icon: "carrot", title: VeggieText.family, accessory: .push)
                }
                .buttonStyle(.row)
                .accessibilityIdentifier("familyRow")
                RowDivider()
            }
            NavigationLink {
                PrivacyView()
            } label: {
                VeggieRow(icon: "hand.raised", title: Words.Settings.privacy, accessory: .push)
            }
            .buttonStyle(.row)
        }
    }

    private func export() {
        do {
            exportFile = ExportFile(url: try model.exportCSV())
        } catch {
            alertText = Words.Failure.export
        }
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gap.group) {
                ForEach(Words.Settings.privacyLines, id: \.self) { line in
                    Text(line)
                        .font(Typo.subheadline.font)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(Gap.screenMargin)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Words.Settings.privacy)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
