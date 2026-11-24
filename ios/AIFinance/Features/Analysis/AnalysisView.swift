import FinanceCore
import SwiftUI

/// 分析分頁。每張卡回答一題，第一行直接是答案。
/// 題目、算法、句子分別在 .analytics/01、05、07。
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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Gap.section) {
                    Text("分析")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    monthSwitcher

                    if let recap { recapCard(recap) }
                    totalCard(report)
                    if !report.categories.isEmpty { categoryCard(report) }
                    if !report.biggest.isEmpty { biggestCard(report) }
                    if model.recentMonths.count >= 2 { recentCard }
                }
                .padding(.horizontal, Theme.Gap.screen)
                .padding(.top, Theme.Gap.pageTop)
                .padding(.bottom, Theme.Gap.section)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // 往上捲的時候，字不要疊到狀態列。
            .safeAreaInset(edge: .top, spacing: 0) {
                Theme.background
                    .frame(height: 1)
                    .background(Theme.background, ignoresSafeAreaEdges: .top)
            }
            .safeAreaInset(edge: .bottom) {
                ToastSlot().padding(.horizontal, Theme.Gap.screen)
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
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("上個月")
            .accessibilityIdentifier("previousMonth")

            Spacer()
            Text(model.days.monthTitle(of: month))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .accessibilityIdentifier("monthTitle")
            Spacer()

            Button {
                pick(model.days.adding(months: 1, toMonthOf: month))
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(month >= thisMonth)
            .accessibilityLabel("下個月")
            .accessibilityIdentifier("nextMonth")
        }
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
            VStack(alignment: .leading, spacing: Theme.Gap.item) {
                HStack {
                    cardTitle(AnalysisText.recapTitle(report))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.accent)
                }
                ForEach(AnalysisText.recapFacts(report), id: \.self) { fact in
                    Text(fact)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recapCard")
    }

    // MARK: - 花了多少

    private func totalCard(_ report: MonthReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Gap.group) {
            VStack(alignment: .leading, spacing: Theme.Gap.tight) {
                cardTitle(AnalysisText.totalTitle(report))
                AmountText(text: Money.format(report.expense), font: .title.bold())
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
                small("收入 \(Money.format(report.income))")
            }

            Divider()

            if report.isCurrent {
                Button {
                    showBudget = true
                } label: {
                    HStack(spacing: Theme.Gap.item) {
                        Text(report.budget.map(AnalysisText.budget) ?? "訂每月預算")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("budgetButton")
            } else {
                small(report.budget.map(AnalysisText.budget) ?? "這個月沒有訂預算。")
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
        return VStack(alignment: .leading, spacing: Theme.Gap.group) {
            cardTitle(AnalysisText.categoryTitle)
            if let text = AnalysisText.categoryAnswer(report) { answer(text, id: "categoryAnswer") }
            if let seen = report.observation {
                Button(AnalysisText.observationLink(seen)) {
                    path.append(CategoryPick(month: report.month, categoryId: seen.category.id))
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("observationLink")
            }
            ForEach(shown) { line in
                Button {
                    path.append(CategoryPick(month: report.month, categoryId: line.id))
                } label: {
                    CategoryRow(line: line, isCurrent: report.isCurrent, scale: scale)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("line_\(line.category.name)")
            }
            if shown.count < report.categories.count {
                Button("看全部 \(report.categories.count) 類") { showAllCategories = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 最大的三筆

    private func biggestCard(_ report: MonthReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Gap.group) {
            cardTitle(AnalysisText.biggestTitle)
            answer(AnalysisText.biggestAnswer(report), id: "biggestAnswer")
            ForEach(report.biggest) { item in
                Button {
                    editing = item
                } label: {
                    TxnRow(item: item, dayText: model.title(for: item.occurredOn))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 最近幾個月

    private var recentCard: some View {
        let months = model.recentMonths
        let scale = max(1, months.compactMap(\.expense).max() ?? 1)
        return VStack(alignment: .leading, spacing: Theme.Gap.group) {
            cardTitle(AnalysisText.recentTitle)
            ForEach(months) { item in
                VStack(alignment: .leading, spacing: Theme.Gap.tight) {
                    HStack {
                        Text(Days.shortMonth(of: item.month)).foregroundStyle(Theme.primaryText)
                        Spacer()
                        Text(item.expense.map(Money.format) ?? AnalysisText.recentMissing)
                            .foregroundStyle(item.expense == nil ? Theme.secondaryText : Theme.primaryText)
                    }
                    .font(.subheadline.monospacedDigit())
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
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
    }

    private func answer(_ text: String, id: String) -> some View {
        Text(text)
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
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
        HStack(alignment: .top, spacing: Theme.Gap.group) {
            CategoryIcon(category: line.category)
            VStack(alignment: .leading, spacing: Theme.Gap.tight) {
                HStack {
                    Text(line.category.name).foregroundStyle(Theme.primaryText)
                    Spacer()
                    AmountText(text: Money.format(line.total), font: .subheadline.weight(.medium))
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.accent)
                }
                .font(.subheadline)
                CompareBar(value: line.routine, extra: line.oneOff, usual: line.usual, scale: scale)
                    .accessibilityHidden(true)
                if let usual = AnalysisText.usual(line, isCurrent: isCurrent) {
                    Text(usual)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 圖

/// 兩條都從 0 開始：上面是這個月（實心平常的花費、空心一次性），下面灰色那段是平常範圍。
struct CompareBar: View {
    let value: Int
    let extra: Int
    let usual: UsualRange?
    let scale: Int

    private static let height: CGFloat = 8
    private static let rangeHeight: CGFloat = 5
    private static let spacing: CGFloat = 3
    /// 範圍很窄的時候也看得到。
    private static let minRange: CGFloat = 8

    private var totalHeight: CGFloat {
        usual == nil ? Self.height : Self.height + Self.spacing + Self.rangeHeight
    }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / CGFloat(max(1, scale))
            VStack(alignment: .leading, spacing: Self.spacing) {
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Theme.primaryText)
                        .frame(width: value > 0 ? max(2, CGFloat(value) * unit) : 0, height: Self.height)
                    if extra > 0 {
                        Capsule()
                            .strokeBorder(Theme.primaryText, lineWidth: 1.5)
                            .frame(width: max(4, CGFloat(extra) * unit), height: Self.height)
                    }
                }
                if let usual {
                    let width = max(Self.minRange, CGFloat(usual.high - usual.low) * unit)
                    Capsule()
                        .fill(Theme.band)
                        .frame(width: width, height: Self.rangeHeight)
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

    private static let height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = max(2, geo.size.width * CGFloat(value) / CGFloat(max(1, scale)))
            if isHollow {
                Capsule().strokeBorder(Theme.primaryText, lineWidth: 1.5).frame(width: width, height: Self.height)
            } else {
                Capsule().fill(Theme.primaryText).frame(width: width, height: Self.height)
            }
        }
        .frame(height: Self.height)
    }
}
