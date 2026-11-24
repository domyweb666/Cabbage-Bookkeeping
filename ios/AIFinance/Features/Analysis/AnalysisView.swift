import FinanceCore
import SwiftUI

/// 分析分頁。每張卡回答一題，第一行直接是答案。
/// 題目、算法、句子分別在 .analytics/01、05、06-08。
struct AnalysisView: View {
    @Environment(LedgerModel.self) private var model

    /// nil 代表這個月。
    @State private var pickedMonth: String?
    @State private var path: [CategoryPick] = []
    @State private var showBudget = false
    @State private var editing: Txn?
    @State private var showAllCategories = false

    /// 月初幾天把上個月的回顧放在最上面。
    private static let recapDays = 7
    private static let topCategories = 5

    private var thisMonth: String { model.days.monthStart(of: model.today) }
    private var month: String { pickedMonth ?? thisMonth }

    var body: some View {
        NavigationStack(path: $path) {
            let report = model.report(month: month)
            DomyPage(title: Words.Analysis.title, background: Theme.background, bottomInset: Theme.pageBottom) {
                if model.loadFailed {
                    EmptyMessage(title: Words.Failure.loadTitle, message: Words.Failure.loadMessage)
                } else {
                    monthSwitcher

                    if let recap { recapCard(recap) }
                    totalCard(report)
                    if !report.categories.isEmpty { categoryCard(report) }
                    if !report.biggest.isEmpty { biggestCard(report) }
                    if model.recentMonths.count >= 2 { recentCard }
                }
            }
            .coversStatusBar()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                ToastSlot().padding(.horizontal, Gap.screenMargin)
            }
            .navigationDestination(for: CategoryPick.self) { CategoryDetailView(pick: $0) }
            .sheet(isPresented: $showBudget) { BudgetSheet() }
            .sheet(item: $editing) { EntrySheet(mode: .edit($0)) }
        }
        .onAppear { model.refreshToday() }
    }

    // MARK: - 月份

    private var monthSwitcher: some View {
        HStack {
            Button {
                pick(model.days.adding(months: -1, toMonthOf: month))
            } label: {
                monthArrow("chevron.left", enabled: true)
            }
            .buttonStyle(.press)
            .accessibilityLabel(Words.Analysis.previousMonth)
            .accessibilityIdentifier("previousMonth")

            Spacer()
            Text(model.days.monthTitle(of: month))
                .font(Typo.headline.font)
                .foregroundStyle(Theme.primaryText)
                .accessibilityIdentifier("monthTitle")
            Spacer()

            Button {
                pick(model.days.adding(months: 1, toMonthOf: month))
            } label: {
                monthArrow("chevron.right", enabled: month < thisMonth)
            }
            .buttonStyle(.press)
            .disabled(month >= thisMonth)
            .accessibilityLabel(Words.Analysis.nextMonth)
            .accessibilityIdentifier("nextMonth")
        }
    }

    private func monthArrow(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name)
            .font(Typo.headline.font)
            .foregroundStyle(enabled ? Theme.accent : Theme.disabledText)
            .frame(width: Metric.touch, height: Metric.touch)
            .contentShape(Rectangle())
    }

    private func pick(_ target: String) {
        pickedMonth = target >= thisMonth ? nil : target
        showAllCategories = false
    }

    // MARK: - 月初回顧

    private var recap: MonthReport? {
        guard month == thisMonth, Days.number(of: model.today) <= Self.recapDays else { return nil }
        let last = model.report(month: model.days.adding(months: -1, toMonthOf: thisMonth))
        return last.expenseCount >= Analysis.minRecords ? last : nil
    }

    private func recapCard(_ report: MonthReport) -> some View {
        Button {
            pick(report.month)
        } label: {
            VStack(alignment: .leading, spacing: Gap.item) {
                HStack {
                    cardTitle(AnalysisText.recapTitle(report))
                    Spacer()
                    Image(systemName: "chevron.right").font(Typo.footnote.font).foregroundStyle(Theme.accent)
                }
                ForEach(AnalysisText.recapFacts(report), id: \.self) { fact in
                    Text(fact)
                        .font(Typo.subheadline.font)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .card()
        }
        .buttonStyle(.press)
        .accessibilityIdentifier("recapCard")
    }

    // MARK: - 花了多少

    private func totalCard(_ report: MonthReport) -> some View {
        VStack(alignment: .leading, spacing: Gap.group) {
            VStack(alignment: .leading, spacing: Gap.tight) {
                cardTitle(AnalysisText.totalTitle(report))
                AmountText(text: Money.format(report.expense), value: report.expense, font: Typo.title1.font)
                    .accessibilityIdentifier("analysisTotal")
            }
            answer(AnalysisText.comparison(report), id: "comparisonText")
            if let usual = report.comparison.range {
                CompareBar(value: report.routine, extra: report.oneOff, usual: usual,
                           scale: max(report.expense, usual.high))
                    .accessibilityHidden(true)
            }
            if report.oneOff > 0, report.comparison.range != nil {
                small(AnalysisText.oneOff(report.oneOff))
            }
            if report.income > 0 {
                small(Words.Analysis.income(report.income))
            }

            Divider()

            if report.isCurrent {
                Button {
                    showBudget = true
                } label: {
                    HStack(spacing: Gap.item) {
                        Text(report.budget.map(AnalysisText.budget) ?? Words.Analysis.setBudget)
                            .font(Typo.subheadline.font)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(Typo.footnote.font)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: Metric.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.row)
                .accessibilityIdentifier("budgetButton")
            } else {
                small(report.budget.map(AnalysisText.budget) ?? Words.Analysis.noBudget)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 花在哪一類

    private func categoryCard(_ report: MonthReport) -> some View {
        let shown = showAllCategories ? report.categories : Array(report.categories.prefix(Self.topCategories))
        let scale = max(
            report.categories.map(\.total).max() ?? 1,
            report.categories.compactMap { $0.usual?.high }.max() ?? 1
        )
        return VStack(alignment: .leading, spacing: Gap.group) {
            cardTitle(AnalysisText.categoryTitle)
            if let text = AnalysisText.categoryAnswer(report) { answer(text, id: "categoryAnswer") }
            if let seen = report.observation {
                Button(AnalysisText.observationLink(seen)) {
                    path.append(CategoryPick(month: report.month, categoryId: seen.category.id))
                }
                .font(Typo.subheadline.font.weight(.semibold))
                .frame(minHeight: Metric.touch)
                .accessibilityIdentifier("observationLink")
            }
            ForEach(shown) { line in
                Button {
                    path.append(CategoryPick(month: report.month, categoryId: line.id))
                } label: {
                    CategoryRow(line: line, isCurrent: report.isCurrent, scale: scale)
                }
                .buttonStyle(.row)
                .accessibilityIdentifier("line_\(line.category.name)")
            }
            if shown.count < report.categories.count {
                Button(Words.Analysis.showAll(report.categories.count)) { showAllCategories = true }
                    .font(Typo.subheadline.font.weight(.semibold))
                    .frame(minHeight: Metric.touch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 最大的三筆

    private func biggestCard(_ report: MonthReport) -> some View {
        VStack(alignment: .leading, spacing: Gap.group) {
            cardTitle(AnalysisText.biggestTitle)
            answer(AnalysisText.biggestAnswer(report), id: "biggestAnswer")
            ForEach(report.biggest) { item in
                Button {
                    editing = item
                } label: {
                    TxnRow(item: item, dayText: model.title(for: item.occurredOn))
                }
                .buttonStyle(.row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 最近幾個月

    private var recentCard: some View {
        let months = model.recentMonths
        let scale = max(1, months.compactMap(\.expense).max() ?? 1)
        return VStack(alignment: .leading, spacing: Gap.group) {
            cardTitle(AnalysisText.recentTitle)
            ForEach(months) { item in
                VStack(alignment: .leading, spacing: Gap.tight) {
                    HStack {
                        Text(Days.shortMonth(of: item.month)).foregroundStyle(Theme.primaryText)
                        Spacer()
                        Text(item.expense.map(Money.format) ?? AnalysisText.recentMissing)
                            .foregroundStyle(item.expense == nil ? Theme.secondaryText : Theme.primaryText)
                    }
                    .font(Typo.subheadline.font.monospacedDigit())
                    // 還沒過完的月份畫空心，不用顏色分。
                    if let expense = item.expense {
                        PlainBar(value: expense, scale: scale, isHollow: item.isCurrent)
                            .accessibilityHidden(true)
                    }
                    if item.isCurrent { small(AnalysisText.recentCurrent) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 共用

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(Typo.subheadline.font)
            .foregroundStyle(Theme.secondaryText)
    }

    private func answer(_ text: String, id: String) -> some View {
        Text(text)
            .font(Typo.body.font.weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .font(Typo.footnote.font)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CategoryPick: Hashable {
    let month: String
    let categoryId: UUID
}

private struct CategoryRow: View {
    let line: CategoryLine
    let isCurrent: Bool
    let scale: Int

    var body: some View {
        HStack(alignment: .top, spacing: Gap.group) {
            CategoryIcon(category: line.category)
            VStack(alignment: .leading, spacing: Gap.tight) {
                HStack {
                    Text(line.category.name).foregroundStyle(Theme.primaryText)
                    Spacer()
                    AmountText(text: Money.format(line.total), font: Typo.subheadline.font.weight(.medium))
                    Image(systemName: "chevron.right").font(Typo.caption.font).foregroundStyle(Theme.accent)
                }
                .font(Typo.subheadline.font)
                CompareBar(value: line.routine, extra: line.oneOff, usual: line.usual, scale: scale)
                    .accessibilityHidden(true)
                if let usual = AnalysisText.usual(line, isCurrent: isCurrent) {
                    Text(usual)
                        .font(Typo.caption.font.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 圖

/// 圖上的尺寸，只有這個檔用。
private enum Chart {
    static let bar: CGFloat = 8
    static let range: CGFloat = 5
    static let gap: CGFloat = 3
    static let outline: CGFloat = 1.5
    /// 金額很小的時候也看得到。
    static let minBar: CGFloat = 2
    static let minOutline: CGFloat = 4
    /// 範圍很窄的時候也看得到。
    static let minRange: CGFloat = 8
}

/// 兩條都從 0 開始：上面是這個月（實心平常的花費、空心一次性），下面灰色那段是平常範圍。
struct CompareBar: View {
    let value: Int
    let extra: Int
    let usual: UsualRange?
    let scale: Int

    private var totalHeight: CGFloat {
        usual == nil ? Chart.bar : Chart.bar + Chart.gap + Chart.range
    }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / CGFloat(max(1, scale))
            VStack(alignment: .leading, spacing: Chart.gap) {
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Theme.primaryText)
                        .frame(width: value > 0 ? max(Chart.minBar, CGFloat(value) * unit) : 0, height: Chart.bar)
                    if extra > 0 {
                        Capsule()
                            .strokeBorder(Theme.primaryText, lineWidth: Chart.outline)
                            .frame(width: max(Chart.minOutline, CGFloat(extra) * unit), height: Chart.bar)
                    }
                }
                if let usual {
                    let width = max(Chart.minRange, CGFloat(usual.high - usual.low) * unit)
                    Capsule()
                        .fill(Theme.band)
                        .frame(width: width, height: Chart.range)
                        .offset(x: min(CGFloat(usual.low) * unit, max(0, geo.size.width - width)))
                }
            }
        }
        .frame(height: totalHeight)
    }
}

struct PlainBar: View {
    let value: Int
    let scale: Int
    let isHollow: Bool

    var body: some View {
        GeometryReader { geo in
            let width = max(Chart.minBar, geo.size.width * CGFloat(value) / CGFloat(max(1, scale)))
            if isHollow {
                Capsule().strokeBorder(Theme.primaryText, lineWidth: Chart.outline).frame(width: width, height: Chart.bar)
            } else {
                Capsule().fill(Theme.primaryText).frame(width: width, height: Chart.bar)
            }
        }
        .frame(height: Chart.bar)
    }
}
