import FinanceCore
import SwiftUI

/// 某個月某一類的每一筆，金額大的在前。看哪幾筆下次可以換個做法。
struct CategoryDetailView: View {
    @Environment(LedgerModel.self) private var model
    let pick: CategoryPick

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editing: Txn?

    private var category: TxCategory? { model.book.find(pick.categoryId) }

    var body: some View {
        let rows = model.expenses(month: pick.month, categoryId: pick.categoryId)
        List {
            Section {
                ForEach(rows) { item in
                    Button {
                        editing = item
                    } label: {
                        TxnRow(item: item, dayText: model.title(for: item.occurredOn))
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
                Text(Words.Analysis.detailHeader(
                    month: pick.month, count: rows.count, total: rows.reduce(0) { $0 + $1.amount }
                ))
                    .font(Typo.footnote.font.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(nil)
                    .accessibilityIdentifier("categoryDetailHeader")
            }
        }
        .ledgerList()
        .animation(reduceMotion ? Motion.changeReduced : Motion.change, value: rows)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(category?.name ?? Words.Ledger.otherCategory)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            ToastSlot().padding(.horizontal, Gap.screenMargin)
        }
        .sheet(item: $editing) { EntrySheet(mode: .edit($0)) }
    }
}

/// 訂每月預算。從這個月起生效，之前的月份不變。
struct BudgetSheet: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    /// 打開時的金額，用來看有沒有動過。
    @State private var savedText = ""
    @State private var hadBudget = false
    @State private var saveFailed = false
    @State private var showFixed = false
    @State private var detent = PresentationDetent.medium
    @FocusState private var focused: Bool

    private var amount: Int? { Money.parse(text) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Gap.group) {
                    // 過去實際花多少，放在要決定的這一刻。
                    Text(AnalysisText.budgetHint(model.monthlyRange))
                        .font(Typo.subheadline.font)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("budgetHint")

                    HStack(spacing: Gap.item) {
                        Text(Words.currency).foregroundStyle(Theme.secondaryText)
                        TextField(Words.Budget.title, text: $text)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .accessibilityIdentifier("budgetAmount")
                    }
                    .font(Typo.title2.font.weight(.regular).monospacedDigit())
                    .card()

                    fixedRow

                    if hadBudget {
                        Button(Words.Budget.clear) { save(0) }
                            .frame(minHeight: Metric.touch)
                            .accessibilityIdentifier("budgetClear")
                    }
                }
                .padding(Gap.screenMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Words.Budget.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showFixed) {
                // 這是彈出來的 sheet，下面沒有分頁列，不用墊高底部按鈕（aboveTabBar）。
                FixedListView().environment(\.tabBarTop, .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Words.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Words.Budget.save) { if let amount { save(amount) } }
                        .fontWeight(.semibold)
                        .disabled(amount == nil)
                        .accessibilityIdentifier("budgetSave")
                }
            }
            .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
                Button(Words.ok, role: .cancel) {}
            } message: {
                Text(Words.Failure.saveMessage)
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(text != savedText)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear {
            if let current = Budget.amount(for: model.days.monthStart(of: model.today), in: model.budgets) {
                text = String(current)
                savedText = text
                hadBudget = true
            }
            focused = true
        }
    }

    /// 固定支出在還能花裡先扣，訂預算的時候順便看得到。
    private var fixedRow: some View {
        VStack(alignment: .leading, spacing: Gap.item) {
            Button {
                focused = false
                detent = .large
                showFixed = true
            } label: {
                HStack(spacing: Gap.item) {
                    Text(Words.Fixed.title).foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 0)
                    Text(Words.Fixed.count(model.activeFixedCount)).foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.right").font(Typo.footnote.font).foregroundStyle(Theme.accent)
                }
                .font(Typo.body.font)
                .padding(.horizontal, Gap.cardPad)
                .frame(minHeight: Metric.row)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.row)
            .accessibilityIdentifier("budgetFixed")
            Text(Words.Budget.fixedHint)
                .font(Typo.footnote.font)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save(_ amount: Int) {
        if model.setBudget(amount) { dismiss() } else { saveFailed = true }
    }
}
