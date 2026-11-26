import Charts
import FinanceCore
import SwiftUI

/// 看法「還能花」（畫布 K2）：還能花當主角，下面每天一根長條，分類收成一行。
/// 沒訂預算時主角改用一句話的結論。數字都從 report 來，跟記帳頁、小工具上的一樣。
struct BudgetModeView: View {
    @Environment(LedgerModel.self) private var model

    let report: MonthReport
    let onBudget: () -> Void
    let onPick: (CategoryPick) -> Void

    var body: some View {
        let daily = Analysis.daily(
            month: report.month, today: model.today, transactions: model.transactions, days: model.days
        )
        VStack(alignment: .leading, spacing: Gap.section) {
            if let status = report.budget {
                budgetHero(status)
            } else {
                sentenceHero
            }
            if let answer = AnalysisText.dailyAnswer(daily) {
                dailyCard(daily, answer: answer)
            }
            categoryLine
        }
    }

    // MARK: - 主角

    private func budgetHero(_ status: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: Gap.group) {
            VStack(alignment: .leading, spacing: Gap.tight) {
                AnalysisCardTitle(AnalysisText.homeBudgetLabel(status))
                AmountText(
                    text: Money.format(AnalysisText.homeBudgetAmount(status)),
                    value: AnalysisText.homeBudgetAmount(status),
                    color: Theme.accentStrong,
                    font: Typo.largeTitle.font
                )
                .accessibilityIdentifier("budgetHero")
                Text(AnalysisText.budgetDays(status))
                    .font(Typo.title3.font)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budgetDays")
            }
            // 實心是記了的，空心是先留給固定支出的，整條是預算。
            CompareBar(
                value: status.spent, extra: status.reserved, usual: nil,
                scale: max(status.budget, status.spent + status.reserved)
            )
            .accessibilityHidden(true)
            AnalysisSmall(AnalysisText.budgetDetail(status))
            if let text = AnalysisText.yearlyPaid(status) { AnalysisSmall(text) }
            if report.isCurrent { budgetButton(Words.AnalysisModes.changeBudget) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var sentenceHero: some View {
        VStack(alignment: .leading, spacing: Gap.group) {
            VStack(alignment: .leading, spacing: Gap.item) {
                Text(AnalysisText.headline(report))
                    .font(Typo.title2.font)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("budgetHero")
                if let detail = AnalysisText.headlineDetail(report) {
                    Text(detail)
                        .font(Typo.subheadline.font)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if report.isCurrent { budgetButton(Words.Analysis.setBudget) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func budgetButton(_ title: String) -> some View {
        Button(action: onBudget) {
            HStack(spacing: Gap.item) {
                Text(title).font(Typo.subheadline.font)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Typo.footnote.font)
            }
            .foregroundStyle(Theme.accent)
            .frame(minHeight: Metric.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .accessibilityIdentifier("budgetButton")
    }

    // MARK: - 每天

    private func dailyCard(_ daily: DailySpending, answer: String) -> some View {
        VStack(alignment: .leading, spacing: Gap.group) {
            AnalysisCardTitle(AnalysisText.dailyTitle)
            AnalysisAnswer(answer, id: "dailyAnswer")
            DailyBars(daily: daily)
            if let text = AnalysisText.dailyHidden(daily.hidden) { AnalysisSmall(text) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 分類收成一行

    @ViewBuilder
    private var categoryLine: some View {
        // 有觀察就去觀察的那一類，跟那一句講的一樣。
        if let text = AnalysisText.categoryAnswer(report),
           let target = report.observation?.category.id ?? report.categories.first?.id {
            VStack(alignment: .leading, spacing: Gap.tight) {
                AnalysisCardTitle(AnalysisText.categoryTitle)
                AnalysisLinkRow(text: text) {
                    onPick(CategoryPick(month: report.month, categoryId: target))
                }
                .accessibilityIdentifier("categoryOneLine")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

/// 圖上的尺寸，只有這個檔用。
private enum BarSize {
    static let height: CGFloat = 110
    static let corner: CGFloat = 3
}

/// 每天一根，固定支出不畫。還沒到的日子留空，看得出這個月還剩多少天。
struct DailyBars: View {
    let daily: DailySpending

    private var axisLabels: [String] {
        guard let first = daily.days.first, let last = daily.days.last else { return [] }
        let middle = daily.days[(daily.days.count - 1) / 2]
        return [first, middle, last].map { Days.slash($0.day) }
    }

    var body: some View {
        Chart(daily.days) { item in
            BarMark(
                x: .value("日", Days.slash(item.day)),
                y: .value("金額", item.amount)
            )
            .foregroundStyle(Theme.primaryText)
            .cornerRadius(BarSize.corner)
            .accessibilityLabel(Days.slash(item.day))
            .accessibilityValue(Words.AnalysisModes.day(item))
        }
        .chartXAxis {
            AxisMarks(values: axisLabels) { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis(.hidden)
        .frame(height: BarSize.height)
        .accessibilityIdentifier("dailyBars")
    }
}
