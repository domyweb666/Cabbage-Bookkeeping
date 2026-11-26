import FinanceCore
import SwiftUI

/// 要編輯的固定支出。item 是 nil 代表新增。
struct FixedTarget: Identifiable {
    let item: FixedExpense?

    var id: String { item?.id.uuidString ?? "new" }
}

/// 固定支出：每月的、每年的各一組。點一列改，左滑刪，刪了可以復原。
/// 設定和訂預算的畫面都會推到這裡。
struct FixedListView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var target: FixedTarget?

    var body: some View {
        let monthly = model.activeFixed(isYearly: false)
        let yearly = model.activeFixed(isYearly: true)
        Group {
            if model.loadFailed {
                EmptyMessage(title: Words.Failure.loadTitle, message: Words.Failure.loadMessage)
            } else if monthly.isEmpty, yearly.isEmpty {
                EmptyMessage(title: Words.Fixed.emptyTitle, message: Words.Fixed.emptyMessage)
            } else {
                List {
                    if !monthly.isEmpty { section(Words.Fixed.monthly, monthly) }
                    if !yearly.isEmpty { section(Words.Fixed.yearly, yearly) }
                }
                .ledgerList()
                .animation(reduceMotion ? Motion.changeReduced : Motion.change, value: monthly + yearly)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle(Words.Fixed.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $target) { FixedEditView(item: $0.item) }
    }

    private var bottomBar: some View {
        VStack(spacing: Gap.group) {
            ToastSlot()
            Button {
                model.refreshToday()
                target = FixedTarget(item: nil)
            } label: {
                Label(Words.Fixed.add, systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: Metric.button)
                    .primaryFill()
                    .clipShape(Capsule())
            }
            .buttonStyle(.press)
            .disabled(model.loadFailed)
            .accessibilityIdentifier("fixedAdd")
        }
        .padding(.horizontal, Gap.screenMargin)
        .padding(.vertical, Gap.group)
        .aboveTabBar()
        .background(Theme.background)
    }

    private func section(_ title: String, _ items: [FixedExpense]) -> some View {
        Section {
            ForEach(items) { item in
                Button {
                    target = FixedTarget(item: item)
                } label: {
                    FixedRow(item: item)
                }
                .buttonStyle(.row)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        model.endFixed(item)
                    } label: {
                        Label(Words.Ledger.delete, systemImage: "trash")
                    }
                }
                .accessibilityIdentifier("fixed_\(model.title(of: item))")
            }
        } header: {
            Text(title)
                .font(Typo.footnote.font)
                .foregroundStyle(Theme.secondaryText)
                .textCase(nil)
        }
    }
}

private struct FixedRow: View {
    @Environment(LedgerModel.self) private var model

    let item: FixedExpense

    var body: some View {
        HStack(spacing: Gap.group) {
            CategoryIcon(category: model.category(of: item))
            VStack(alignment: .leading, spacing: Gap.tight) {
                Text(model.title(of: item))
                    .font(Typo.headline.font)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(AnalysisText.schedule(item.schedule))
                if item.schedule.isYearly { Text(AnalysisText.share(item.amount)) }
            }
            .font(Typo.footnote.font.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: Gap.item)
            AmountText(text: Money.grouped(item.amount), font: Typo.headline.font)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
