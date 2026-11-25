import FinanceCore
import SwiftUI

/// 新增或改一項固定支出：多少錢、哪一天、哪一類。
/// 每月和每年之間不能換，改的時候就不顯示那個切換。
struct FixedEditView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: FixedExpense?

    @State private var draft = FixedDraft()
    /// 剛打開時的內容，用來看有沒有動過。
    @State private var opened: FixedDraft?
    @State private var saveFailed = false
    @FocusState private var focus: Field?

    private enum Field { case amount, name }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Gap.item), count: 4)

    private var isDirty: Bool { opened.map { $0 != draft } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Gap.section) {
                    if item == nil { kindPicker }
                    amountAndName
                    dayPart
                    categoryPart
                    if item != nil { deletePart }
                }
                .padding(.horizontal, Gap.screenMargin)
                .padding(.vertical, Gap.group)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(item == nil ? Words.Fixed.add : Words.Fixed.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
                Button(Words.ok, role: .cancel) {}
            } message: {
                Text(Words.Failure.saveMessage)
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: load)
        .onChange(of: draft.month) { _, _ in draft.clampDay() }
        .onChange(of: draft.isYearly) { _, _ in draft.clampDay() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(Words.cancel) { dismiss() }
                .accessibilityIdentifier("fixedCancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(Words.Fixed.save) { save() }
                .fontWeight(.semibold)
                .disabled(draft.fields == nil)
                .accessibilityIdentifier("fixedSave")
        }
    }

    private var kindPicker: some View {
        Picker(Words.Fixed.kind, selection: $draft.isYearly) {
            Text(Words.Fixed.monthly).tag(false)
            Text(Words.Fixed.yearly).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("fixedKind")
    }

    private var amountAndName: some View {
        VStack(spacing: 0) {
            HStack(spacing: Gap.item) {
                Text(Words.currency).foregroundStyle(Theme.secondaryText)
                TextField(Words.Fixed.amount, text: $draft.amountText, prompt: prompt(Words.Fixed.amount))
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .amount)
                    .accessibilityIdentifier("fixedAmount")
            }
            .font(Typo.title2.font.weight(.regular).monospacedDigit())
            .frame(minHeight: Metric.row)
            .padding(.vertical, Gap.tight)
            RowDivider()
            TextField(Words.Fixed.name, text: $draft.name, prompt: prompt(Words.Fixed.name))
                .font(Typo.body.font)
                .focused($focus, equals: .name)
                .submitLabel(.done)
                .onSubmit { focus = nil }
                .frame(minHeight: Metric.row)
                .accessibilityIdentifier("fixedName")
        }
        .padding(.horizontal, Gap.cardPad)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: - 哪一天

    private var dayPart: some View {
        VStack(alignment: .leading, spacing: Gap.item) {
            HStack(spacing: Gap.item) {
                Text(Words.Fixed.day)
                    .font(Typo.body.font)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 0)
                if draft.isYearly {
                    Picker(Words.Fixed.monthLabel, selection: $draft.month) {
                        ForEach(1...12, id: \.self) { Text(Words.Fixed.month($0)).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("fixedMonth")
                }
                Picker(Words.Fixed.dayLabel, selection: $draft.day) {
                    ForEach(1...draft.lastDay, id: \.self) { number in
                        Text(draft.isYearly ? Words.Fixed.yearDay(number) : Words.Fixed.monthDay(number)).tag(number)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("fixedDay")
            }
            .pickerStyle(.menu)
            .padding(.horizontal, Gap.cardPad)
            .frame(minHeight: Metric.row)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

            if let next {
                note(AnalysisText.nextDue(next)).accessibilityIdentifier("fixedNext")
            }
            if !draft.isYearly, draft.day > 28 { note(Words.Fixed.lateDay) }
        }
    }

    /// 照現在填的，下一次會記在哪天。金額還沒填也看得到。
    private var next: String? {
        let fields = FixedFields(
            amount: draft.amount ?? 0, categoryId: draft.categoryId ?? UUID(), schedule: draft.schedule
        )
        let preview = item.map { $0.applying(fields, on: model.today) }
            ?? FixedExpense(fields: fields, startsOn: model.today, createdAt: Date())
        return model.nextDue(of: preview)
    }

    // MARK: - 分類

    private var categoryPart: some View {
        VStack(alignment: .leading, spacing: Gap.item) {
            Text(Words.Fixed.category)
                .font(Typo.subheadline.font)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: typeSize.isAccessibilitySize ? Gap.group : Gap.tight) {
                ForEach(model.book.choices(.expense, keeping: item?.categoryId)) { category in
                    CategoryCell(category: category, isSelected: category.id == draft.categoryId) {
                        if draft.categoryId != category.id { Haptics.selected() }
                        draft.categoryId = category.id
                        focus = nil
                    }
                    .accessibilityLabel(category.name)
                    .accessibilityAddTraits(category.id == draft.categoryId ? .isSelected : [])
                    .accessibilityIdentifier("fixedCategory_\(category.name)")
                }
            }
            .padding(Gap.item)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private var deletePart: some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            Button(Words.Fixed.delete, role: .destructive) {
                guard let item else { return }
                dismiss()
                model.endFixed(item)
            }
            .frame(minHeight: Metric.touch)
            .accessibilityIdentifier("fixedDelete")
            note(Words.Fixed.deleteNote)
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Theme.secondaryText)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typo.footnote.font.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func load() {
        guard opened == nil else { return }
        if let item {
            draft = FixedDraft(
                item: item,
                categoryId: model.book.selection(item.categoryId, kind: .expense, keeping: item.categoryId)
            )
        } else {
            draft = FixedDraft(today: model.today)
        }
        opened = draft
    }

    private func save() {
        guard let fields = draft.fields else { return }
        let done = item.map { model.updateFixed($0, with: fields) } ?? model.addFixed(fields)
        if done { dismiss() } else { saveFailed = true }
    }
}

/// 畫面上填的內容。
private struct FixedDraft: Equatable {
    var isYearly = false
    var amountText = ""
    var name = ""
    var month = 1
    var day = 1
    var categoryId: UUID?

    init() {}

    /// 新增：日子先帶今天。
    init(today: String) {
        month = Int(today.dropFirst(5).prefix(2)) ?? 1
        day = max(1, Days.number(of: today))
    }

    init(item: FixedExpense, categoryId: UUID?) {
        amountText = String(item.amount)
        name = item.note
        self.categoryId = categoryId
        switch item.schedule {
        case .monthly(let day):
            self.day = day
        case .yearly(let month, let day):
            isYearly = true
            self.month = month
            self.day = day
        }
    }

    var amount: Int? { Money.parse(amountText) }

    var schedule: FixedSchedule {
        isYearly ? .yearly(month: month, day: day) : .monthly(day: day)
    }

    /// 每年的照那個月有幾天，2 月給到 29 號。
    var lastDay: Int {
        guard isYearly else { return 31 }
        switch month {
        case 2: return 29
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    mutating func clampDay() {
        day = min(day, lastDay)
    }

    /// 可以存的內容。金額或分類還沒填是 nil。
    var fields: FixedFields? {
        guard let amount, let categoryId else { return nil }
        return FixedFields(amount: amount, categoryId: categoryId, note: name, schedule: schedule)
    }
}
