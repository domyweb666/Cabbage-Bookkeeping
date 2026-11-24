import FinanceCore
import SwiftUI

/// 記一筆：按金額、點分類、記下。改一筆也用同一個畫面。
struct EntrySheet: View {
    enum Mode: Hashable {
        case new
        case edit(Txn)
    }

    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var type: TxType = .expense
    @State private var pad = AmountPad()
    @State private var categoryId: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var isOneOff = false
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var saveFailed = false
    @FocusState private var noteFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Gap.item), count: 4)

    private var original: Txn? {
        if case .edit(let row) = mode { return row }
        return nil
    }

    private var canSave: Bool { pad.value > 0 && categoryId != nil }

    /// 可以選到的最後一天是今天。
    private var latestDate: Date { model.days.date(of: model.today) ?? Date() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amount
                ScrollView {
                    VStack(spacing: Theme.Gap.section) {
                        categoryGrid
                        details
                    }
                    .padding(.horizontal, Theme.Gap.screen)
                    .padding(.vertical, Theme.Gap.group)
                }
                .scrollDismissesKeyboard(.interactively)

                // 打備註時讓位給系統鍵盤。
                if !noteFocused {
                    Keypad(pad: $pad, canSave: canSave, onSave: save)
                        .padding(.horizontal, Theme.Gap.screen)
                        .padding(.vertical, Theme.Gap.group)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog("刪除這筆紀錄？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let original {
                        dismiss()
                        model.delete(original)
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("沒有存成功", isPresented: $saveFailed) {
                Button("好", role: .cancel) {}
            } message: {
                Text("手機空間可能不夠，清出空間後再按一次。")
            }
        }
        .tint(Theme.accent)
        .onAppear(perform: load)
        .onChange(of: type) { _, newType in
            // 換成收入或支出時，對不上的分類要清掉。
            if Categories.find(categoryId)?.kind != newType { categoryId = nil }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
                .accessibilityIdentifier("entryCancel")
        }
        ToolbarItem(placement: .principal) {
            Picker("類型", selection: $type) {
                ForEach(TxType.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        ToolbarItem(placement: .primaryAction) {
            if noteFocused {
                Button("完成") { noteFocused = false }
            } else if original != nil {
                Button("刪除", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("entryDelete")
            }
        }
    }

    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Gap.tight) {
            Text("NT$")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            AmountText(
                text: Money.grouped(pad.value),
                color: pad.value == 0 ? Theme.secondaryText : Theme.primaryText,
                font: .system(.largeTitle, design: .rounded).bold()
            )
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityIdentifier("entryAmount")
        }
        .padding(.horizontal, Theme.Gap.screen)
        .padding(.top, Theme.Gap.group)
        .padding(.bottom, Theme.Gap.item)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Gap.item) {
            ForEach(Categories.of(type)) { category in
                CategoryCell(category: category, isSelected: category.id == categoryId) {
                    categoryId = category.id
                }
            }
        }
    }

    private var details: some View {
        VStack(spacing: Theme.Gap.group) {
            HStack(spacing: Theme.Gap.group) {
                DatePicker("日期", selection: $date, in: ...latestDate, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_TW"))
                    .environment(\.timeZone, model.days.timeZone)
                    .accessibilityIdentifier("entryDate")
                Spacer(minLength: 0)
                if type == .expense {
                    Button {
                        isOneOff.toggle()
                    } label: {
                        Label("一次性", systemImage: isOneOff ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(isOneOff ? Theme.accent : Theme.secondaryText)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOneOff ? .isSelected : [])
                    .accessibilityIdentifier("entryOneOff")
                }
            }
            if isOneOff, type == .expense {
                Text("跟平常比的時候，不算這一筆。")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            TextField("備註，可以不填", text: $note)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
                .padding(.horizontal, Theme.Gap.card)
                .frame(minHeight: 48)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                .accessibilityIdentifier("entryNote")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        date = latestDate
        guard let original else { return }
        type = original.type
        pad = AmountPad(value: original.amount)
        categoryId = original.categoryId
        date = model.days.date(of: original.occurredOn) ?? latestDate
        note = original.note
        isOneOff = original.isOneOff
    }

    private func save() {
        guard canSave, let categoryId else { return }
        let fields = TxnFields(
            type: type,
            amount: pad.value,
            occurredOn: model.days.day(of: date),
            categoryId: categoryId,
            note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)),
            isOneOff: isOneOff
        )
        let done = original.map { model.update($0, with: fields) } ?? model.add(fields)
        if done { dismiss() } else { saveFailed = true }
    }
}

private struct CategoryCell: View {
    let category: TxCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Gap.tight) {
                Image(systemName: category.icon)
                    .font(.title3)
                    .frame(height: 28)
                Text(category.name)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(isSelected ? Theme.accent : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("category_\(category.name)")
    }
}

/// 數字鍵盤。右邊一欄是退格和記下。
private struct Keypad: View {
    @Binding var pad: AmountPad
    let canSave: Bool
    let onSave: () -> Void

    private static let keyHeight: CGFloat = 52
    private static let tallHeight: CGFloat = keyHeight * 2 + Theme.Gap.item

    var body: some View {
        HStack(spacing: Theme.Gap.item) {
            VStack(spacing: Theme.Gap.item) {
                row(["1", "2", "3"])
                row(["4", "5", "6"])
                row(["7", "8", "9"])
                row(["00", "0"])
            }
            VStack(spacing: Theme.Gap.item) {
                Button {
                    pad.backspace()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: Self.tallHeight)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                }
                .accessibilityLabel("退格")
                .accessibilityIdentifier("key_back")

                Button(action: onSave) {
                    Text("記下")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: Self.tallHeight)
                        .background(Theme.accent.opacity(canSave ? 1 : 0.35))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                }
                .disabled(!canSave)
                .accessibilityIdentifier("entrySave")
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primaryText)
    }

    private func row(_ keys: [String]) -> some View {
        HStack(spacing: Theme.Gap.item) {
            ForEach(keys, id: \.self) { key in
                Button {
                    pad.press(key)
                } label: {
                    Text(key)
                        .font(.title2.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                }
                .accessibilityIdentifier("key_\(key)")
            }
        }
    }
}
