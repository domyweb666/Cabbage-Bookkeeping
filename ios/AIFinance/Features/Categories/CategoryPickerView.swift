import FinanceCore
import SwiftUI

/// 常用分類：勾起來的會出現在記一筆的畫面，順序照這裡排。改了就存，不用另外按儲存。
/// 從記一筆進來是彈出來的（有「完成」），從設定進來是往右推的。
///
/// 一列三個動作各有自己的位置：點左邊整塊是勾選，筆是編輯，右邊的系統把手是拖曳。
struct CategoryPickerView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kind: TxType
    @State private var target: CategoryTarget?
    @State private var confirmReset = false
    @State private var saveFailed = false
    private let showsDone: Bool

    init(kind: TxType = .expense, showsDone: Bool) {
        _kind = State(initialValue: kind)
        self.showsDone = showsDone
    }

    private var isLastOne: Bool { model.book.shown(of: kind).count == 1 }

    var body: some View {
        List {
            Section {
                ForEach(model.book.shown(of: kind)) { category in
                    row(category, isShown: true)
                }
                .onMove { offsets, place in
                    change { $0.move(kind, from: offsets, to: place) }
                }
            } header: {
                header(Words.Categories.shown)
            }

            Section {
                Button {
                    target = CategoryTarget(kind: kind, category: nil)
                } label: {
                    Label(Words.Categories.add, systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("newCategory")
                Button(Words.Categories.reset) { confirmReset = true }
                    .buttonStyle(.borderless)
                    .disabled(model.book.isStandard(kind))
                    .accessibilityIdentifier("resetCategories")
            }

            ForEach(model.book.hiddenGroups(kind)) { group in
                Section {
                    ForEach(group.items) { category in
                        row(category, isShown: false)
                    }
                } header: {
                    header(group.name)
                }
            }
        }
        .ledgerList()
        // 一直開著編輯模式，系統的拖曳把手才會一直在。
        .environment(\.editMode, .constant(.active))
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { switcher }
        .navigationTitle(Words.Categories.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if showsDone {
                    Button(Words.done) { dismiss() }
                        .accessibilityIdentifier("categoriesDone")
                }
            }
        }
        .navigationDestination(item: $target) { CategoryEditView(target: $0) }
        .alert(Words.Categories.resetTitle(kind), isPresented: $confirmReset) {
            Button(Words.Categories.reset, role: .destructive) { change { $0.reset(kind) } }
            Button(Words.cancel, role: .cancel) {}
        } message: {
            Text(Words.Categories.resetMessage(kind))
        }
        .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
            Button(Words.ok, role: .cancel) {}
        } message: {
            Text(Words.Failure.saveToast)
        }
    }

    /// 切支出／收入，下面一句說明。固定在上面，不跟著捲走。
    private var switcher: some View {
        VStack(alignment: .leading, spacing: Gap.item) {
            Picker(Words.Entry.kind, selection: $kind) {
                ForEach(TxType.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(isLastOne ? Words.Categories.keepOne : Words.Categories.hint)
                .font(Typo.footnote.font)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("categoriesHint")
        }
        .padding(.horizontal, Gap.screenMargin)
        .padding(.vertical, Gap.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Typo.footnote.font)
            .foregroundStyle(Theme.secondaryText)
            .textCase(nil)
    }

    private func row(_ category: TxCategory, isShown: Bool) -> some View {
        HStack(spacing: Gap.item) {
            Button {
                toggle(category)
            } label: {
                HStack(spacing: Gap.group) {
                    Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                        .font(Typo.title3.font)
                        .foregroundStyle(isShown ? Theme.accent : Theme.secondaryText)
                        .accessibilityHidden(true)
                    CategoryIcon(category: category)
                    Text(category.name)
                        .font(Typo.body.font)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Metric.touch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.row)
            .accessibilityLabel(category.name)
            .accessibilityAddTraits(isShown ? .isSelected : [])
            .accessibilityHint(isShown && isLastOne ? Words.Categories.keepOne : "")
            .accessibilityAction(named: Words.Categories.moveUp) { shift(category, by: -1) }
            .accessibilityAction(named: Words.Categories.moveDown) { shift(category, by: 1) }
            .accessibilityIdentifier("pick_\(category.name)")

            Button {
                target = CategoryTarget(kind: kind, category: category)
            } label: {
                Image(systemName: "pencil")
                    .font(Typo.body.font)
                    .foregroundStyle(Theme.accent)
                    .frame(width: Metric.touch, height: Metric.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.row)
            .accessibilityLabel(Words.Categories.edit(category.name))
            .accessibilityIdentifier("edit_\(category.name)")
        }
    }

    private func toggle(_ category: TxCategory) {
        if model.book.isShown(category.id) {
            guard !isLastOne else {
                Haptics.failed()
                return
            }
            change { $0.hide(category.id) }
        } else {
            change { $0.show(category.id) }
        }
        Haptics.selected()
    }

    private func shift(_ category: TxCategory, by step: Int) {
        guard model.book.canShift(category.id, by: step) else { return }
        change { $0.shift(category.id, by: step) }
    }

    private func change(_ edit: (inout CategoryBook) -> Void) {
        let saved = model.changeBook { book in
            edit(&book)
            return true
        }
        if !saved { saveFailed = true }
    }
}
