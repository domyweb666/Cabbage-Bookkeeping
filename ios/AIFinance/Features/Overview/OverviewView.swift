import Charts
import FinanceCore
import SwiftUI

/// 本月概覽（規格 7.6）：月份切換、總支出、總收入、分類長條圖、扣掉一次性支出後的日常開銷。
/// 所有數字來自後端的 monthly_overview。
struct OverviewView: View {
    @Environment(TimelineViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.backupPromptShown) private var backupPromptShown = false

    @State private var month = Days.taipei.monthStart(of: Days.taipei.day(of: Date()))
    @State private var overview: MonthlyOverview?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showBackupHint = false
    @State private var showSettings = false

    private let days = Days.taipei

    private var isCurrentMonth: Bool {
        month == days.monthStart(of: model.today)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacing(2)) {
                    monthSwitcher

                    if let overview {
                        totals(overview)
                        if overview.byCategory.isEmpty {
                            VStack(spacing: Theme.spacing(1.5)) {
                                MascotView(action: .shrug).frame(height: 130)
                                Text("這個月還沒有支出紀錄。")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .card(padding: Theme.spacing(3))
                        } else {
                            categoryChart(overview)
                        }
                        if showBackupHint { backupHint }
                    } else if let errorMessage {
                        VStack(spacing: Theme.unit) {
                            Text(errorMessage).font(.subheadline).foregroundStyle(Theme.secondaryText)
                            Button("再試一次") { Task { await load() } }
                        }
                        .frame(maxWidth: .infinity)
                        .card(padding: Theme.spacing(3))
                    } else {
                        ProgressView().padding(.top, Theme.spacing(6))
                    }
                }
                .padding(Theme.spacing(2))
            }
            .background(Theme.background)
            .navigationTitle("概覽")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .tint(Theme.accent)
        .task(id: month) { await load() }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                month = days.adding(months: -1, toMonthOf: month)
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("上個月")
            .accessibilityIdentifier("previousMonth")

            Spacer()
            Text(days.monthTitle(of: month))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .accessibilityIdentifier("monthTitle")
            Spacer()

            Button {
                month = days.adding(months: 1, toMonthOf: month)
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("下個月")
        }
    }

    private func totals(_ overview: MonthlyOverview) -> some View {
        VStack(spacing: Theme.spacing(1.5)) {
            HStack(spacing: Theme.spacing(1.5)) {
                stat("總支出", overview.totalExpense, Theme.expense)
                stat("總收入", overview.totalIncome, Theme.income)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("扣掉一次性支出後的日常開銷")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                AmountText(text: Money.format(overview.routineExpense), font: .title2.weight(.bold))
                if overview.oneOffExpense > 0 {
                    Text("一次性支出 \(Money.format(overview.oneOffExpense)) 沒有算在裡面")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .opacity(isLoading ? 0.5 : 1)
    }

    private func stat(_ title: String, _ amount: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondaryText)
            AmountText(text: Money.format(amount), color: color, font: .title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func categoryChart(_ overview: MonthlyOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            Text("支出分類")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Chart(overview.byCategory) { entry in
                BarMark(
                    x: .value("金額", Double(entry.total)),
                    y: .value("分類", entry.name)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(6)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(Money.grouped(entry.total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: 0...max(1, Double(overview.byCategory.map(\.total).max() ?? 1) * 1.25))
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Theme.primaryText)
                }
            }
            .frame(height: CGFloat(overview.byCategory.count) * 36 + 8)
            .accessibilityLabel(
                "支出分類：" + overview.byCategory.map { "\($0.name) \(Money.format($0.total))" }.joined(separator: "、")
            )
        }
        .card()
    }

    /// 尚未綁定且已記超過 20 筆時提示一次，之後不再打擾（規格 8.3）。
    private var backupHint: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text("要不要備份？")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("目前資料只跟著這支手機。綁定 Apple ID 之後，換手機或重裝都能取回。")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button("到設定綁定") { showSettings = true }
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            overview = try await model.transactionRepository.overview(monthOf: month)
            errorMessage = nil
        } catch {
            overview = nil
            errorMessage = model.isOnline ? "讀不到這個月的資料，請稍後再試。" : "離線時看不到概覽，連上網路後再試。"
        }

        if !showBackupHint, isCurrentMonth {
            let linked = await model.transactionRepository.isLinked
            if BackupPrompt.shouldShow(transactionCount: model.transactions.count, isLinked: linked, alreadyShown: backupPromptShown) {
                showBackupHint = true
                backupPromptShown = true
            }
        }
    }
}
