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
    @Environment(\.dynamicTypeSize) private var typeSize
    let mode: Mode

    @State private var type: TxType = .expense
    @State private var pad = AmountPad()
    @State private var categoryId: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var isOneOff = false
    /// 剛打開時的內容，用來看有沒有動過。
    @State private var opened: EntryForm?
    @State private var showCategories = false
    @State private var confirmDelete = false
    @State private var saveFailed = false
    @FocusState private var noteFocused: Bool

    private static let contentID = "entryContent"
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Gap.item), count: 4)

    private var original: Txn? {
        if case .edit(let row) = mode { return row }
        return nil
    }

    private var form: EntryForm {
        EntryForm(
            type: type,
            amount: pad.value,
            occurredOn: model.days.day(of: date),
            categoryId: categoryId,
            note: note,
            isOneOff: isOneOff
        )
    }

    private var canSave: Bool { form.fields != nil }

    /// 動過的內容不給滑掉，要走就按「取消」。
    private var isDirty: Bool {
        guard let opened else { return false }
        return form != opened
    }

    /// 可以選到的最後一天是今天。
    private var latestDate: Date { model.days.date(of: model.today) ?? Date() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amount
                categoryHeader
                ScrollViewReader { proxy in
                    ScrollView { scrolled }
                    // 平常字級：白卡固定，格子在卡片裡捲。大字：卡片跟著日期、備註一起捲。
                    .background(isLarge ? Color.clear : Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: isLarge ? 0 : Theme.cardRadius, style: .continuous))
                    .padding(.horizontal, isLarge ? 0 : Gap.screenMargin)
                    // 打開就看得到選好的那一格。
                    .onChange(of: opened) { _, form in
                        guard let id = form?.categoryId else { return }
                        Task { proxy.scrollTo(id) }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // 分類超過一個畫面時閃一下捲軸，看得出下面還有。
                    .scrollIndicatorsFlash(onAppear: true)
                    .scrollIndicatorsFlash(trigger: type)
                    // 鍵盤升完再捲到底，備註欄才不會貼著鍵盤。
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        guard noteFocused, typeSize.isAccessibilitySize else { return }
                        withAnimation(Motion.change) { proxy.scrollTo(Self.contentID, anchor: .bottom) }
                    }
                }

                // 分類再多，日期和備註都固定在鍵盤上面看得到。
                if !typeSize.isAccessibilitySize {
                    details
                        .padding(.horizontal, Gap.screenMargin)
                        .padding(.top, Gap.item)
                        .padding(.bottom, noteFocused ? Gap.group : 0)
                }

                // 打備註時讓位給系統鍵盤。
                if !noteFocused {
                    Keypad(pad: $pad, canSave: canSave, onSave: save)
                        .padding(.horizontal, Gap.screenMargin)
                        .padding(.vertical, Gap.group)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(Words.Entry.deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(Words.Entry.deleteConfirm, role: .destructive) {
                    if let original {
                        dismiss()
                        model.delete(original)
                    }
                }
                Button(Words.cancel, role: .cancel) {}
            }
            .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
                Button(Words.ok, role: .cancel) {}
            } message: {
                Text(Words.Failure.saveMessage)
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(isDirty)
        .sheet(isPresented: $showCategories) {
            NavigationStack { CategoryPickerView(kind: type, showsDone: true) }
                .tint(Theme.accent)
        }
        .onAppear(perform: load)
        .onChange(of: type) { _, newType in
            // 換成收入或支出時，對不上的分類要清掉。
            categoryId = model.book.selection(categoryId, kind: newType, keeping: original?.categoryId)
        }
        .onChange(of: model.book) { _, book in
            // 選好的分類不再顯示，就當作還沒選。
            categoryId = book.selection(categoryId, kind: type, keeping: original?.categoryId)
        }
    }

    private var isLarge: Bool { typeSize.isAccessibilitySize }

    @ViewBuilder
    private var scrolled: some View {
        if isLarge {
            VStack(spacing: Gap.section) {
                categoryGrid
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                // 字放到很大時位置不夠，日期和備註跟著一起捲。
                details
            }
            .padding(.horizontal, Gap.screenMargin)
            .padding(.bottom, Gap.item)
            .id(Self.contentID)
        } else {
            categoryGrid.id(Self.contentID)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(Words.cancel) { dismiss() }
                .accessibilityIdentifier("entryCancel")
        }
        ToolbarItem(placement: .principal) {
            Picker(Words.Entry.kind, selection: $type) {
                ForEach(TxType.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: Theme.Part.kindPicker)
        }
        ToolbarItem(placement: .primaryAction) {
            if noteFocused {
                Button(Words.done) { noteFocused = false }
            } else if original != nil {
                Button(Words.Entry.delete, role: .destructive) { confirmDelete = true }
                    .tint(Theme.destructive)
                    .accessibilityIdentifier("entryDelete")
            }
        }
    }

    /// 這一筆是什麼、多少錢。
    private var amount: some View {
        HStack(spacing: Gap.group) {
            PickedCategory(category: model.book.find(categoryId))
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: Gap.tight) {
                Text(Words.currency)
                    .font(Typo.subheadline.font)
                    .foregroundStyle(Theme.secondaryText)
                AmountText(
                    text: Money.grouped(pad.value),
                    value: pad.value,
                    color: pad.value == 0 ? Theme.secondaryText : Theme.primaryText,
                    font: .system(.largeTitle, design: .rounded).bold()
                )
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("entryAmount")
            }
            // 位置不夠的時候先縮分類名，金額最後才縮。
            .layoutPriority(1)
        }
        .padding(.horizontal, Gap.cardPad)
        .padding(.vertical, Gap.group)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .padding(.horizontal, Gap.screenMargin)
        .padding(.top, Gap.item)
    }

    /// 固定在格子上面，分類捲到哪裡都按得到「編輯」。
    private var categoryHeader: some View {
        HStack {
            Text(Words.Entry.category)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Gap.item)
            Button {
                noteFocused = false
                showCategories = true
            } label: {
                Text(Words.Entry.editCategories)
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: Metric.touch, minHeight: Metric.touch, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .accessibilityLabel(Words.Entry.editCategoriesSpoken)
            .accessibilityIdentifier("editCategories")
        }
        .font(Typo.subheadline.font)
        .padding(.horizontal, Gap.screenMargin + Gap.tight)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: columns, spacing: isLarge ? Gap.group : Gap.tight) {
            ForEach(model.book.choices(type, keeping: original?.categoryId)) { category in
                CategoryCell(category: category, isSelected: category.id == categoryId) {
                    if categoryId != category.id { Haptics.selected() }
                    categoryId = category.id
                }
                .accessibilityLabel(category.name)
                .accessibilityAddTraits(category.id == categoryId ? .isSelected : [])
                .accessibilityIdentifier("category_\(category.name)")
            }
        }
        .padding(Gap.item)
    }

    private var details: some View {
        VStack(spacing: Gap.group) {
            // 字放大到一排放不下時，改成上下兩排。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Gap.group) {
                    datePicker
                    Spacer(minLength: 0)
                    oneOffButton
                }
                // 收入沒有「一次性」，高度也不變，日期才不會跳。
                .frame(minHeight: Metric.touch)
                VStack(alignment: .leading, spacing: Gap.group) {
                    datePicker
                    oneOffButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField(
                Words.Entry.note, text: $note,
                prompt: Text(Words.Entry.note).foregroundStyle(Theme.secondaryText)
            )
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
                .padding(.horizontal, Gap.cardPad)
                .frame(minHeight: Metric.field)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                .accessibilityIdentifier("entryNote")
        }
    }

    private var datePicker: some View {
        DatePicker(Words.Entry.date, selection: $date, in: ...latestDate, displayedComponents: .date)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "zh_TW"))
            .environment(\.timeZone, model.days.timeZone)
            .accessibilityIdentifier("entryDate")
    }

    @ViewBuilder
    private var oneOffButton: some View {
        if type == .expense {
            Button {
                isOneOff.toggle()
            } label: {
                // 說明寫在同一排，勾了也不會多一行把分類格擠掉。
                Label(
                    isOneOff ? Words.Entry.oneOffOn : Words.Ledger.oneOff,
                    systemImage: isOneOff ? "checkmark.circle.fill" : "circle"
                )
                    .font(Typo.subheadline.font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(isOneOff ? Theme.accent : Theme.secondaryText)
                    .frame(minHeight: Metric.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .accessibilityAddTraits(isOneOff ? .isSelected : [])
            .accessibilityIdentifier("entryOneOff")
        }
    }

    private func load() {
        guard opened == nil else { return }
        let start = original.map { EntryForm(editing: $0, book: model.book) } ?? EntryForm(today: model.today)
        opened = start
        type = start.type
        pad = AmountPad(value: start.amount)
        categoryId = start.categoryId
        date = model.days.date(of: start.occurredOn) ?? latestDate
        note = start.note
        isOneOff = start.isOneOff
    }

    private func save() {
        guard let fields = form.fields else { return }
        let done = original.map { model.update($0, with: fields) } ?? model.add(fields)
        if done { dismiss() } else { saveFailed = true }
    }
}

/// 金額左邊：選了哪一類。還沒選是一格虛線。
private struct PickedCategory: View {
    let category: TxCategory?

    var body: some View {
        HStack(spacing: Gap.group) {
            if let category {
                CategoryIcon(category: category)
            } else {
                RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
                    .strokeBorder(Theme.tertiaryText, style: Theme.Part.emptyBadge)
                    .frame(width: Theme.Part.badge, height: Theme.Part.badge)
                    .accessibilityHidden(true)
            }
            Text(category?.name ?? Words.Entry.pickCategory)
                .font(category == nil ? Typo.body.font : Typo.title3.font)
                .foregroundStyle(category == nil ? Theme.secondaryText : Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(category.map { Words.Entry.picked($0.name) } ?? Words.Entry.pickCategory)
        }
    }
}

/// 分類格。記一筆和固定支出共用。
struct CategoryCell: View {
    let category: TxCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Gap.tight) {
                Image(systemName: category.icon)
                    .font(Typo.body.font)
                    // 色塊大小固定，圖示放大到這裡為止，不撐出去。
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(isSelected ? Theme.onTint : Theme.primaryText)
                    .frame(width: Theme.Part.cellIconWidth, height: Theme.Part.cellIconHeight)
                    .background(
                        isSelected ? Theme.tint(category.tint) : Theme.background,
                        in: RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
                    )
                Text(category.name)
                    .font(Typo.footnote.font.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Part.cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
    }
}

/// 數字鍵盤。右邊一欄是退格和記下。
private struct Keypad: View {
    @Binding var pad: AmountPad
    let canSave: Bool
    let onSave: () -> Void

    private static let keyHeight = Metric.button
    private static let tallHeight: CGFloat = keyHeight * 2 + Gap.item

    var body: some View {
        HStack(spacing: Gap.item) {
            VStack(spacing: Gap.item) {
                row(["1", "2", "3"])
                row(["4", "5", "6"])
                row(["7", "8", "9"])
                row(["00", "0"])
            }
            VStack(spacing: Gap.item) {
                Button {
                    pad.backspace()
                } label: {
                    Image(systemName: "delete.left")
                        .font(Typo.title2.font.weight(.regular))
                        .frame(maxWidth: .infinity, minHeight: Self.tallHeight)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                }
                .accessibilityLabel(Words.Entry.backspace)
                .accessibilityIdentifier("key_back")

                Button(action: onSave) {
                    Text(Words.Entry.save)
                        .frame(maxWidth: .infinity, minHeight: Self.tallHeight)
                        .primaryFill()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                }
                .disabled(!canSave)
                .accessibilityIdentifier("entrySave")
            }
            .frame(width: Theme.Part.keySide)
        }
        .buttonStyle(.press)
        .foregroundStyle(Theme.primaryText)
    }

    private func row(_ keys: [String]) -> some View {
        HStack(spacing: Gap.item) {
            ForEach(keys, id: \.self) { key in
                Button {
                    pad.press(key)
                } label: {
                    Text(key)
                        .font(Typo.title2.font.weight(.regular).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
                }
                .accessibilityIdentifier("key_\(key)")
            }
        }
    }
}
