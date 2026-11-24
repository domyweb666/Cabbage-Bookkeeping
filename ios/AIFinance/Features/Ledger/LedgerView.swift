import FinanceCore
import SwiftUI

/// 記帳分頁：本月支出、每天的明細、底部一顆「記一筆」。
struct LedgerView: View {
    @Environment(LedgerModel.self) private var model

    @State private var editing: Txn?
    @State private var showNew = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Theme.Gap.group) {
                ToastSlot()
                Button {
                    model.refreshToday()
                    showNew = true
                } label: {
                    Label("記一筆", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.loadFailed)
                .accessibilityIdentifier("addButton")
            }
            .padding(.horizontal, Theme.Gap.screen)
            .padding(.vertical, Theme.Gap.group)
            .background(Theme.background)
        }
        .sheet(isPresented: $showNew) { EntrySheet(mode: .new) }
        .sheet(item: $editing) { EntrySheet(mode: .edit($0)) }
    }

    private var header: some View {
        let report = model.report(month: model.today)
        return VStack(alignment: .leading, spacing: Theme.Gap.tight) {
            Text("本月支出")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            AmountText(text: Money.format(report.expense), font: .largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let budget = report.budget {
                AmountText(text: AnalysisText.homeBudget(budget), color: Theme.secondaryText, font: .subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Gap.screen)
        .padding(.top, Theme.Gap.section)
        .padding(.bottom, Theme.Gap.group)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monthTotal")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Gap.item) {
            Text(model.loadFailed ? "紀錄讀不出來" : "還沒有紀錄")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(model.loadFailed ? "先把 App 整個關掉再開一次。紀錄還在，沒有被刪掉。" : "按下面的「記一筆」，選金額和分類就好。")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Gap.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Button {
                            editing = item
                        } label: {
                            TxnRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.delete(item)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack(spacing: Theme.Gap.item) {
                        Text(model.title(for: section.day))
                        Spacer()
                        if section.incomeTotal > 0 {
                            Text("+" + Money.grouped(section.incomeTotal)).foregroundStyle(Theme.income)
                        }
                        if section.expenseTotal > 0 {
                            Text("-" + Money.grouped(section.expenseTotal))
                        }
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

/// 一筆紀錄的列。
struct TxnRow: View {
    let item: Txn
    /// 在分類明細裡要顯示日期，在每天的明細裡不用。
    var dayText: String?

    private var subtitle: String {
        var parts: [String] = []
        if let dayText { parts.append(dayText) }
        if !item.note.isEmpty, dayText == nil { parts.append(item.category?.name ?? "其他") }
        if item.isOneOff { parts.append("一次性") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Theme.Gap.group) {
            CategoryIcon(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Gap.item)
            AmountText(
                text: Money.signed(item.amount, type: item.type),
                color: item.type == .income ? Theme.income : Theme.primaryText,
                font: .body.weight(.medium)
            )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)，\(item.category?.name ?? "其他")，\(item.type.label) \(Money.format(item.amount))")
    }
}

struct CategoryIcon: View {
    let category: TxCategory?

    var body: some View {
        Image(systemName: category?.icon ?? "questionmark.circle")
            .font(.body)
            .foregroundStyle(Theme.accent)
            .frame(width: 36, height: 36)
            .background(Theme.accent.opacity(0.12))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// 提示條的位置。每個會動到紀錄的畫面底部放一個。
struct ToastSlot: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        Group {
            if let toast = model.toast {
                HStack(spacing: Theme.Gap.group) {
                    Text(toast.message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityIdentifier("toastText")
                    Spacer(minLength: 0)
                    if toast.undo != nil {
                        Button("復原") { model.undo(toast) }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("undoButton")
                    }
                }
                .padding(.horizontal, Theme.Gap.card)
                .frame(minHeight: 48)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}
