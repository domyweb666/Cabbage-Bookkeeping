import FinanceCore
import SwiftUI

/// 要編輯的分類。category 是 nil 代表新增。
struct CategoryTarget: Hashable, Identifiable {
    let kind: TxType
    let category: TxCategory?

    var id: String { category?.id.uuidString ?? "new" }
}

/// 新增分類、改名字與圖示。順序也可以在這裡一格一格移，不用拖。
/// 按「存分類」才一次存，按「取消」就當作沒動過。
struct CategoryEditView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let target: CategoryTarget
    @State private var name: String
    @State private var icon: String
    /// 往前（負）或往後（正）移了幾格，還沒存。
    @State private var moved = 0
    @State private var saveFailed = false
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: Metric.touch), spacing: Gap.item)]

    init(target: CategoryTarget) {
        self.target = target
        _name = State(initialValue: target.category?.name ?? "")
        _icon = State(initialValue: target.category?.icon ?? Categories.icons[0])
    }

    private var categoryID: UUID? { target.category?.id }

    /// 內建分類原本的樣子，自己新增的是 nil。
    private var builtIn: TxCategory? { categoryID.flatMap { Categories.find($0) } }

    /// 動過的內容不給滑掉，要走就按「取消」。
    private var isDirty: Bool {
        name != (target.category?.name ?? "") || icon != (target.category?.icon ?? Categories.icons[0]) || moved != 0
    }

    private var problem: CategoryNameProblem? {
        model.book.problem(with: name, kind: target.kind, excluding: categoryID)
    }

    /// 還沒開始打字就不先說「要有名字」。
    private var shownProblem: CategoryNameProblem? {
        problem == .empty && target.category == nil ? nil : problem
    }

    private var isCustom: Bool { categoryID.map { model.book.isCustom($0) } ?? false }

    private var isLastShown: Bool {
        guard let id = categoryID else { return false }
        return model.book.isShown(id) && model.book.shown(of: target.kind).count == 1
    }

    var body: some View {
        List {
            nameSection
            if let id = categoryID, model.book.isShown(id) { orderSection(id) }
            iconSection
            if let id = categoryID, let builtIn, model.book.isRenamed(id) { restoreSection(builtIn) }
            if isCustom { deleteSection }
        }
        .ledgerList()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(target.category == nil ? Words.CategoryEdit.newTitle : Words.CategoryEdit.editTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(isDirty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Words.cancel) { dismiss() }
                    .accessibilityIdentifier("categoryCancel")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(Words.CategoryEdit.save) { save() }
                    .fontWeight(.semibold)
                    .disabled(problem != nil)
                    .accessibilityIdentifier("categorySave")
            }
        }
        .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
            Button(Words.ok, role: .cancel) {}
        } message: {
            Text(Words.Failure.saveMessage)
        }
        .alert(Words.CategoryEdit.deleteTitle(target.category?.name ?? ""), isPresented: $confirmDelete) {
            Button(Words.CategoryEdit.delete, role: .destructive) { delete() }
            Button(Words.cancel, role: .cancel) {}
        } message: {
            Text(Words.CategoryEdit.deleteMessage)
        }
    }

    private var nameSection: some View {
        Section {
            TextField(Words.CategoryEdit.namePrompt, text: $name)
                .font(Typo.body.font)
                .submitLabel(.done)
                .accessibilityLabel(Words.CategoryEdit.nameSection)
                .accessibilityIdentifier("categoryName")
        } header: {
            header(Words.CategoryEdit.nameSection)
        } footer: {
            if let shownProblem {
                Text(Words.CategoryEdit.problem(shownProblem))
                    .font(Typo.footnote.font)
                    .foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("categoryNameProblem")
            }
        }
    }

    /// 拖曳以外的另一條路，放在圖示前面才找得到。
    private func orderSection(_ id: UUID) -> some View {
        Section {
            Button(Words.CategoryEdit.moveUp) { moved -= 1 }
                .disabled(!model.book.canShift(id, by: moved - 1))
                .accessibilityIdentifier("categoryMoveUp")
            Button(Words.CategoryEdit.moveDown) { moved += 1 }
                .disabled(!model.book.canShift(id, by: moved + 1))
                .accessibilityIdentifier("categoryMoveDown")
        } header: {
            header(Words.CategoryEdit.orderSection)
        }
    }

    private var iconSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: Gap.item) {
                ForEach(Array(Categories.icons.enumerated()), id: \.element) { index, symbol in
                    Button {
                        if icon != symbol { Haptics.selected() }
                        icon = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(Typo.body.font)
                            .foregroundStyle(icon == symbol ? Theme.onAccent : Theme.primaryText)
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .frame(width: Metric.touch, height: Metric.touch)
                            .background(icon == symbol ? Theme.accent : Theme.background, in: Circle())
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel(Words.CategoryEdit.icon(index + 1))
                    .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                    .accessibilityIdentifier("icon_\(symbol)")
                }
            }
            .padding(.vertical, Gap.item)
        } header: {
            header(Words.CategoryEdit.iconSection)
        }
    }

    private func restoreSection(_ original: TxCategory) -> some View {
        Section {
            Button(Words.CategoryEdit.restore) {
                name = original.name
                icon = original.icon
            }
            .disabled(name == original.name && icon == original.icon)
            .accessibilityIdentifier("categoryRestore")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(Words.CategoryEdit.delete, role: .destructive) { confirmDelete = true }
                .disabled(isLastShown)
                .accessibilityIdentifier("categoryDelete")
        } footer: {
            if isLastShown {
                Text(Words.CategoryEdit.lastOne)
                    .font(Typo.footnote.font)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Typo.footnote.font)
            .foregroundStyle(Theme.secondaryText)
            .textCase(nil)
    }

    private func save() {
        guard problem == nil else { return }
        let saved = model.changeBook { book in
            if let id = categoryID { return book.edit(id, name: name, icon: icon, moved: moved) }
            return book.add(name, icon: icon, kind: target.kind, at: Date())
        }
        guard saved else {
            saveFailed = true
            return
        }
        Haptics.saved()
        dismiss()
    }

    private func delete() {
        guard let id = categoryID else { return }
        if model.changeBook({ $0.delete(id, at: Date()) }) {
            Haptics.deleted()
            dismiss()
        } else {
            saveFailed = true
        }
    }
}
