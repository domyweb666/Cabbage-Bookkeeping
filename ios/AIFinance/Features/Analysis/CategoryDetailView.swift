import FinanceCore
import SwiftUI

/// 某個月某一類的每一筆，金額大的在前。看哪幾筆下次可以換個做法。
struct CategoryDetailView: View {
    @Environment(LedgerModel.self) private var model
    let pick: CategoryPick

    @State private var editing: Txn?

    private var category: TxCategory? { Categories.find(pick.categoryId) }

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
                Text("\(Days.shortMonth(of: pick.month)) \(rows.count) 筆，共 \(Money.format(rows.reduce(0) { $0 + $1.amount }))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(nil)
                    .accessibilityIdentifier("categoryDetailHeader")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(category?.name ?? "其他")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            ToastSlot().padding(.horizontal, Theme.Gap.screen)
        }
        .sheet(item: $editing) { EntrySheet(mode: .edit($0)) }
    }
}

/// 訂每月預算。從這個月起生效，之前的月份不變。
struct BudgetSheet: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var hadBudget = false
    @State private var saveFailed = false
    @FocusState private var focused: Bool

    private var amount: Int? { Money.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Gap.group) {
                // 過去實際花多少，放在要決定的這一刻。
                Text(AnalysisText.budgetHint(model.monthlyRange))
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budgetHint")

                HStack(spacing: Theme.Gap.item) {
                    Text("NT$").foregroundStyle(Theme.secondaryText)
                    TextField("每月預算", text: $text)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .accessibilityIdentifier("budgetAmount")
                }
                .font(.title2.monospacedDigit())
                .card()

                if hadBudget {
                    Button("不訂預算") { save(0) }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("budgetClear")
                }
                Spacer()
            }
            .padding(Theme.Gap.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("每月預算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存") { if let amount { save(amount) } }
                        .fontWeight(.semibold)
                        .disabled(amount == nil)
                        .accessibilityIdentifier("budgetSave")
                }
            }
            .alert("沒有存成功", isPresented: $saveFailed) {
                Button("好", role: .cancel) {}
            } message: {
                Text("手機空間可能不夠，清出空間後再按一次。")
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium, .large])
        .onAppear {
            if let current = Budget.amount(for: model.days.monthStart(of: model.today), in: model.budgets) {
                text = String(current)
                hadBudget = true
            }
            focused = true
        }
    }

    private func save(_ amount: Int) {
        if model.setBudget(amount) { dismiss() } else { saveFailed = true }
    }
}
