import FinanceCore
import SwiftUI

/// 記帳分頁：本月支出、每天的明細、底部一顆「記一筆」。
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
                header
                if model.isEmpty {
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

    private var header: some View {
        let report = model.report(month: model.today)
        return VStack(alignment: .leading, spacing: Gap.tight) {
            Text(Words.Ledger.monthTotal)
                .font(Typo.subheadline.font)
                .foregroundStyle(Theme.secondaryText)
            AmountText(text: Money.format(report.expense), value: report.expense, font: Typo.largeTitle.font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let budget = report.budget {
                AmountText(text: AnalysisText.homeBudget(budget), color: Theme.secondaryText, font: Typo.subheadline.font)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Gap.screenMargin)
        .padding(.top, Gap.pageTop)
        .padding(.bottom, Gap.group)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monthTotal")
    }

    private var list: some View {
        let sections = model.sections
        return List {
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
                    HStack(spacing: Gap.item) {
                        Text(model.title(for: section.day))
                        Spacer()
                        if section.incomeTotal > 0 {
                            Text("+" + Money.grouped(section.incomeTotal)).foregroundStyle(Theme.income)
                        }
                        if section.expenseTotal > 0 {
                            Text("-" + Money.grouped(section.expenseTotal))
                        }
                    }
                    .font(Typo.footnote.font.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(nil)
                }
            }
        }
        .ledgerList()
        .animation(reduceMotion ? nil : Motion.change, value: sections)
    }
}

/// 一筆紀錄的列。
struct TxnRow: View {
    @Environment(LedgerModel.self) private var model

    let item: Txn
    /// 在分類明細裡要顯示日期，在每天的明細裡不用。
    var dayText: String?

    private var category: TxCategory { model.category(of: item) }

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
                    .font(Typo.body.font)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typo.caption.font)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Gap.item)
            AmountText(
                text: Money.signed(item.amount, type: item.type),
                color: item.type == .income ? Theme.income : Theme.primaryText,
                font: Typo.body.font.weight(.medium)
            )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title(of: item))，\(category.name)，\(item.type.label) \(Money.format(item.amount))")
    }
}

struct CategoryIcon: View {
    let category: TxCategory

    var body: some View {
        Image(systemName: category.icon)
            .font(Typo.body.font)
            .foregroundStyle(Theme.accent)
            .frame(width: Theme.Part.badge, height: Theme.Part.badge)
            .background(Theme.accentSoft, in: Circle())
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
