import FinanceCore
import SwiftUI

/// 確認卡（規格 7.3）：從底部升起的半屏。每筆草稿一張小卡，說明為什麼需要確認，欄位可以直接改。
struct ConfirmSheet: View {
    @Environment(TimelineViewModel.self) private var model
    let request: ConfirmRequest

    @State private var drafts: [Draft] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var problems: [String] {
        drafts.enumerated().flatMap { index, draft in
            draft.problems(today: model.today).map { drafts.count > 1 ? "第 \(index + 1) 筆\($0)" : $0 }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                    Text("「\(request.rawText)」")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, Theme.unit)

                    ForEach($drafts) { $draft in
                        DraftCard(draft: $draft, categories: model.categories, today: model.today)
                    }

                    if let message = errorMessage ?? problems.first {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.expense)
                            .padding(.horizontal, Theme.unit)
                    }
                }
                .padding(Theme.spacing(2))
            }
            .background(Theme.background)
            .navigationTitle(drafts.count > 1 ? "確認這 \(drafts.count) 筆" : "確認這筆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.cancelConfirm(request) }
                        .accessibilityIdentifier("confirmCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "儲存中" : "全部確認") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving || !problems.isEmpty)
                        .accessibilityIdentifier("confirmAll")
                }
            }
        }
        .tint(Theme.accent)
        .onAppear { drafts = request.drafts }
        .onChange(of: request.id) { _, _ in
            drafts = request.drafts
            errorMessage = nil
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            errorMessage = await model.confirm(request, drafts: drafts)
            isSaving = false
        }
    }
}

/// 一筆草稿的小卡：金額、品項、分類、日期都可以點擊修改。
struct DraftCard: View {
    @Binding var draft: Draft
    let categories: [TxCategory]
    let today: String

    @State private var amountText = ""

    private var choices: [TxCategory] {
        categories.filter { $0.kind == draft.type }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Days.taipei.date(of: draft.occurredOn) ?? Date() },
            set: { draft.occurredOn = Days.taipei.day(of: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            if !draft.reasons.isEmpty {
                // 用一行字說明為什麼需要確認。
                Label(draft.reasons.joined(separator: "、"), systemImage: "questionmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(draft.type == .income ? "+NT$" : "NT$")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(draft.type == .income ? Theme.income : Theme.primaryText)
                TextField("金額", text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(draft.type == .income ? Theme.income : Theme.primaryText)
                    .onChange(of: amountText) { _, value in
                        draft.amount = Money.parse(value) ?? 0
                    }
                    .accessibilityIdentifier("draftAmount")
            }

            TextField("品項", text: $draft.item)
                .font(.body)
                .accessibilityIdentifier("draftItem")

            Divider()

            HStack {
                Menu {
                    ForEach(choices) { category in
                        Button {
                            draft.categoryId = category.id
                            draft.categoryName = category.name
                        } label: {
                            Label(category.name, systemImage: category.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: categories.first { $0.id == draft.categoryId }?.icon ?? "tag")
                        Text(draft.categoryName ?? "選分類")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(draft.categoryId == nil ? Theme.expense : Theme.accent)
                }
                .accessibilityIdentifier("draftCategory")

                Spacer()

                DatePicker("日期", selection: dateBinding, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_TW"))
                    .environment(\.timeZone, Days.taipei.timeZone)
            }
        }
        .card()
        .onAppear { amountText = draft.amount > 0 ? String(draft.amount) : "" }
    }
}
