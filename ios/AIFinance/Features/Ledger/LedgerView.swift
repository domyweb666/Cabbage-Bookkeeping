import FinanceCore
import SwiftUI

/// 記帳分頁：月份、本月支出、每天的明細、底部一顆「記一筆」。
struct LedgerView: View {
    @Environment(LedgerModel.self) private var model

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editing: Txn?
    @State private var showNew = false

    var body: some View {
        VStack(spacing: 0) {
            // 讀不出來的時候不顯示總數，0 元是錯的。
            if model.loadFailed {
                EmptyMessage(title: Words.Failure.loadTitle, message: Words.Failure.loadMessage)
            } else {
                title
                if model.isEmpty {
                    summary
                        .card()
                        .padding(.horizontal, Gap.screenMargin)
                    EmptyMessage(title: Words.Ledger.emptyTitle, message: Words.Ledger.emptyMessage)
                } else {
                    list
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Gap.group) {
                ToastSlot()
                Button {
                    model.refreshToday()
                    showNew = true
                } label: {
                    Label(Words.Ledger.add, systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: Metric.button)
                        .primaryFill()
                        .clipShape(Capsule())
                }
                .buttonStyle(.press)
                .disabled(model.loadFailed)
                .accessibilityIdentifier("addButton")
            }
            .padding(.horizontal, Gap.screenMargin)
            .padding(.vertical, Gap.group)
            .background(Theme.background)
        }
        .sheet(isPresented: $showNew) { EntrySheet(mode: .new) }
        .sheet(item: $editing) { EntrySheet(mode: .edit($0)) }
    }

    /// 現在是哪個月。固定在上面，總額那張卡跟著捲。
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.item) {
            Text(Days.shortMonth(of: model.today))
                .font(Typo.largeTitle.font)
                .foregroundStyle(Theme.primaryText)
            Text(String(model.today.prefix(4)))
                .font(Typo.subheadline.font)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Gap.screenMargin)
        .padding(.top, Gap.pageTop)
        .padding(.bottom, Gap.group)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.days.monthTitle(of: model.today))
        .accessibilityAddTraits(.isHeader)
    }

    private var summary: some View {
        let report = model.report(month: model.today)
        // 標籤一排、數字一排才對得齊。字放大到一排放不下時，改成上下兩塊。
        return ViewThatFits(in: .horizontal) {
            VStack(spacing: Gap.tight) {
                HStack {
                    caption(Words.Ledger.monthTotal)
                    Spacer(minLength: Gap.group)
                    if let budget = report.budget { caption(AnalysisText.homeBudgetLabel(budget)) }
                }
                HStack(alignment: .firstTextBaseline) {
                    monthAmount(report)
                    Spacer(minLength: Gap.group)
                    if let budget = report.budget { budgetAmount(budget) }
                }
            }
            VStack(alignment: .leading, spacing: Gap.group) {
                VStack(alignment: .leading, spacing: Gap.tight) {
                    caption(Words.Ledger.monthTotal)
                    monthAmount(report)
                }
                if let budget = report.budget {
                    VStack(alignment: .leading, spacing: Gap.tight) {
                        caption(AnalysisText.homeBudgetLabel(budget))
                        budgetAmount(budget)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Words.Ledger.monthSpoken(total: report.expense, budget: report.budget.map(AnalysisText.homeBudget))
        )
        .accessibilityIdentifier("monthTotal")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Typo.subheadline.font)
            .foregroundStyle(Theme.secondaryText)
    }

    private func monthAmount(_ report: MonthReport) -> some View {
        AmountText(text: Money.format(report.expense), value: report.expense, font: Typo.title1.font)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func budgetAmount(_ budget: BudgetStatus) -> some View {
        let amount = AnalysisText.homeBudgetAmount(budget)
        return AmountText(text: Money.grouped(amount), value: amount, color: Theme.accentStrong, font: Typo.title3.font)
            .lineLimit(1)
    }

    private var list: some View {
        let sections = model.sections
        return List {
            Section {
                summary.listRowInsets(
                    EdgeInsets(top: Gap.cardPad, leading: Gap.cardPad, bottom: Gap.cardPad, trailing: Gap.cardPad)
                )
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Button {
                            editing = item
                        } label: {
                            TxnRow(item: item)
                        }
                        .buttonStyle(.row)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.delete(item)
                            } label: {
                                Label(Words.Ledger.delete, systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    DayHeader(section: section)
                }
            }
        }
        .ledgerList()
        .contentMargins(.top, 0, for: .scrollContent)
        .animation(reduceMotion ? nil : Motion.change, value: sections)
    }
}

/// 一天的標題：日期粗、星期灰，右邊是小計。只有一筆的時候小計跟那筆一樣，不重複寫。
private struct DayHeader: View {
    @Environment(LedgerModel.self) private var model

    let section: DaySection

    var body: some View {
        let label = model.days.sectionLabel(for: section.day, today: model.today)
        // 字放大到一排放不下時，小計換到下一排。
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Gap.item) {
                date(label)
                Spacer(minLength: Gap.item)
                totals
            }
            VStack(alignment: .leading, spacing: Gap.tight) {
                date(label)
                totals
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 0, leading: Gap.tight, bottom: Gap.item, trailing: Gap.tight))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func date(_ label: (title: String, detail: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.item) {
            Text(label.title)
                .font(Typo.title3.font.monospacedDigit())
                .foregroundStyle(Theme.primaryText)
            Text(label.detail)
                .font(Typo.footnote.font.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var totals: some View {
        if section.items.count > 1 {
            HStack(alignment: .firstTextBaseline, spacing: Gap.item) {
                if section.incomeTotal > 0 {
                    Text(Money.listed(section.incomeTotal, type: .income)).foregroundStyle(Theme.income)
                }
                if section.expenseTotal > 0 {
                    Text(Words.Ledger.dayTotal(section.expenseTotal)).foregroundStyle(Theme.secondaryText)
                }
            }
            .font(Typo.subheadline.font.monospacedDigit())
            .lineLimit(1)
        }
    }
}

/// 一筆紀錄的列。
struct TxnRow: View {
    @Environment(LedgerModel.self) private var model

    let item: Txn
    /// 在分類明細裡要顯示日期，在每天的明細裡不用。
    var dayText: String?

    private var category: TxCategory { model.category(of: item) }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var subtitle: String {
        var parts: [String] = []
        if let dayText { parts.append(dayText) }
        if !item.note.isEmpty, dayText == nil { parts.append(category.name) }
        if item.isOneOff { parts.append(Words.Ledger.oneOff) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Gap.group) {
            CategoryIcon(category: category)
            VStack(alignment: .leading, spacing: Gap.tight) {
                Text(model.title(of: item))
                    .font(Typo.headline.font)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typo.footnote.font)
                        .foregroundStyle(Theme.secondaryText)
                        // 字放大時日期和「一次性」會排不下，不限行數。
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
            }
            Spacer(minLength: Gap.item)
            AmountText(
                text: Money.listed(item.amount, type: item.type),
                color: item.type == .income ? Theme.income : Theme.primaryText,
                font: Typo.headline.font
            )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title(of: item))，\(category.name)，\(item.type.label) \(Money.format(item.amount))")
    }
}

/// 分類色塊。顏色照大組，圖示照分類。
struct CategoryIcon: View {
    let category: TxCategory

    var body: some View {
        Image(systemName: category.icon)
            .font(Typo.body.font)
            // 色塊大小固定，圖示放大到這裡為止，不撐出去。
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .foregroundStyle(Theme.onTint)
            .frame(width: Theme.Part.badge, height: Theme.Part.badge)
            .background(
                Theme.tint(category.tint), in: RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// 提示條的位置。每個會動到紀錄的畫面底部放一個。
struct ToastSlot: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        Group {
            if let toast = model.toast {
                HStack(spacing: Gap.group) {
                    Text(toast.message)
                        .font(Typo.subheadline.font)
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityIdentifier("toastText")
                    Spacer(minLength: 0)
                    if toast.undo != nil {
                        Button(Words.Ledger.undo) { model.undo(toast) }
                            .font(Typo.subheadline.font.weight(.semibold))
                            .frame(minHeight: Metric.touch)
                            .accessibilityIdentifier("undoButton")
                    }
                }
                .padding(.horizontal, Gap.cardPad)
                .frame(minHeight: Metric.field)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .transition(.opacity)
            }
        }
        .animation(Motion.change, value: model.toast)
    }
}
