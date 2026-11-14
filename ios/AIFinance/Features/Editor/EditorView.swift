import FinanceCore
import SwiftUI

/// 編輯畫面（規格 7.5）。也是純手動新增的入口（從主畫面長按送出鍵進來）。
struct EditorView: View {
    enum Mode {
        case new
        case edit(Txn)
    }

    @Environment(TimelineViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var type: TxType = .expense
    @State private var amountText = ""
    @State private var item = ""
    @State private var categoryId: UUID?
    @State private var date = Date()
    @State private var merchant = ""
    @State private var tagsText = ""
    @State private var nature: Nature?
    @State private var note = ""
    @State private var rawText: String?
    @State private var loaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    private var original: Txn? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    private var choices: [TxCategory] {
        model.categories.filter { $0.kind == type }
    }

    private var tags: [String] {
        var seen = Set<String>()
        return tagsText
            .split(whereSeparator: { "，,、 　".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(5)
            .map { String($0.prefix(20)) }
    }

    private var problem: String? {
        if Money.parse(amountText) == nil { return "金額要是大於 0 的整數" }
        if item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "需要填品項" }
        if categoryId == nil { return "需要選分類" }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("類型", selection: $type) {
                        ForEach(TxType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    LabeledContent("金額") {
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                            .accessibilityIdentifier("editorAmount")
                    }
                    LabeledContent("品項") {
                        TextField("買了什麼", text: $item)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editorItem")
                    }
                    Picker("分類", selection: $categoryId) {
                        Text("未選").tag(UUID?.none)
                        ForEach(choices) { category in
                            Label(category.name, systemImage: category.icon).tag(UUID?.some(category.id))
                        }
                    }
                    .accessibilityIdentifier("editorCategory")
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_TW"))
                        .environment(\.timeZone, Days.taipei.timeZone)
                }

                Section {
                    LabeledContent("商家") {
                        TextField("選填", text: $merchant).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("標籤") {
                        TextField("用逗號分開", text: $tagsText).multilineTextAlignment(.trailing)
                    }
                    if type == .expense {
                        Picker("性質", selection: $nature) {
                            Text("未分").tag(Nature?.none)
                            ForEach(Nature.allCases, id: \.self) { Text($0.label).tag(Nature?.some($0)) }
                        }
                    }
                    TextField("備註", text: $note, axis: .vertical).lineLimit(1...4)
                }

                if let rawText {
                    Section {
                        Text(rawText)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                    } header: {
                        Text("原話").textCase(nil)
                    }
                }

                if let message = errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.expense)
                    }
                }

                if original != nil {
                    Section {
                        Button("刪除這筆", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(original == nil ? "手動新增" : "編輯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "儲存中" : "儲存") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving || problem != nil)
                        .accessibilityIdentifier("editorSave")
                }
            }
            .confirmationDialog("刪除這筆紀錄？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let original {
                        dismiss()
                        Task { await model.delete(original) }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後畫面下方可以馬上復原。")
            }
        }
        .tint(Theme.accent)
        .onAppear(perform: load)
        .onChange(of: type) { _, newType in
            // 切換收支類型時，分類要跟著換成對得上的。
            guard loaded, model.category(categoryId)?.kind != newType else { return }
            let matching = model.categories.filter { $0.kind == newType }
            categoryId = matching.count == 1 ? matching[0].id : nil
            if newType == .income { nature = nil }
        }
        .task {
            if let entryId = original?.entryId {
                rawText = await model.transactionRepository.rawText(entryId: entryId)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        if let original {
            type = original.type
            amountText = String(original.amount)
            item = original.item
            categoryId = original.categoryId
            date = Days.taipei.date(of: original.occurredOn) ?? Date()
            merchant = original.merchant ?? ""
            tagsText = original.tags.joined(separator: "、")
            nature = original.nature
            note = original.note ?? ""
        }
        loaded = true
    }

    private func save() {
        guard let amount = Money.parse(amountText), let categoryId else { return }
        let trimmed: (String) -> String? = { text in
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        // 手動新增或改過分類，就標成使用者指定：之後自動流程不會覆寫，同商家下次自動套用。
        let source = original.map { $0.categoryId == categoryId ? $0.categorySource : "user" } ?? "user"
        let fields = TxnFields(
            type: type, amount: amount, occurredOn: Days.taipei.day(of: date),
            item: trimmed(item) ?? "", merchant: trimmed(merchant), categoryId: categoryId,
            categorySource: source, tags: tags, nature: type == .expense ? nature : nil, note: trimmed(note)
        )

        isSaving = true
        errorMessage = nil
        Task {
            do {
                let saved: Txn
                if let original {
                    saved = try await model.transactionRepository.update(id: original.id, fields: fields)
                } else {
                    saved = try await model.transactionRepository.create(fields)
                }
                model.applySaved(saved)
                dismiss()
            } catch let error as BackendError {
                errorMessage = error.message
            } catch {
                errorMessage = "儲存失敗，請稍後再試。"
            }
            isSaving = false
        }
    }
}
