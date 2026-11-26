import FinanceCore
import SwiftUI

/// 常用分類：上面「顯示中」的格子長得跟記一筆一模一樣，一眼看得到每一格在哪。
/// 下面是還沒放進去的，照大組排成格子。點一下就放進去或拿出來，改了就存，不用另外按儲存。
/// 按住一格可以改名字和圖示。不提供排序（多米 2026-11-26 QC-0015：不需要）。
/// 從記一筆進來是彈出來的（有「完成」），從設定進來是往右推的。
struct CategoryPickerView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var kind: TxType
    @State private var target: CategoryTarget?
    @State private var confirmReset = false
    @State private var saveFailed = false
    private let showsDone: Bool

    /// 跟記一筆同一種四欄。
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Gap.item), count: 4)

    init(kind: TxType = .expense, showsDone: Bool) {
        _kind = State(initialValue: kind)
        self.showsDone = showsDone
    }

    private var isLastOne: Bool { model.book.shown(of: kind).count == 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gap.group) {
                header(Words.Categories.shown)
                grid(model.book.shown(of: kind), isShown: true)
                    .card()

                actions

                ForEach(model.book.hiddenGroups(kind)) { group in
                    header(group.name)
                    grid(group.items, isShown: false)
                        .card()
                }
            }
            .padding(.horizontal, Gap.screenMargin)
            .padding(.bottom, Theme.pageBottom)
            .animation(reduceMotion ? Motion.changeReduced : Motion.change, value: model.book.shown(of: kind).map(\.id))
        }
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
        // 用 sheet 不用往右推：推進去的畫面，左滑返回有時擋不住，打到一半的字會丟。
        .sheet(item: $target) { target in
            NavigationStack { CategoryEditView(target: target) }
                .tint(Theme.accent)
        }
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

    /// 新增、恢復預設。放在顯示中下面，還沒放進去的上面。
    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                target = CategoryTarget(kind: kind, category: nil)
            } label: {
                Label(Words.Categories.add, systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: Metric.touch, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.row)
            .foregroundStyle(Theme.accent)
            .accessibilityIdentifier("newCategory")
            Divider()
            Button {
                confirmReset = true
            } label: {
                Text(Words.Categories.reset)
                    .frame(maxWidth: .infinity, minHeight: Metric.touch, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.row)
            .foregroundStyle(model.book.isStandard(kind) ? Theme.disabledText : Theme.accent)
            .disabled(model.book.isStandard(kind))
            .accessibilityIdentifier("resetCategories")
        }
        .font(Typo.body.font)
        .padding(.horizontal, Gap.cardPad)
        .padding(.vertical, Gap.tight)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Typo.footnote.font)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, Gap.cardPad)
            .padding(.top, Gap.item)
            .accessibilityAddTraits(.isHeader)
    }

    private func grid(_ items: [TxCategory], isShown: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: Gap.tight) {
            ForEach(items) { category in
                cell(category, isShown: isShown)
            }
        }
    }

    /// 顯示中的格子有顏色，跟記一筆選中的樣子一樣；還沒放進去的是灰底。
    private func cell(_ category: TxCategory, isShown: Bool) -> some View {
        CategoryCell(category: category, isSelected: isShown) { toggle(category) }
            .contextMenu {
                Button {
                    target = CategoryTarget(kind: kind, category: category)
                } label: {
                    Label(Words.Categories.edit(category.name), systemImage: "pencil")
                }
            }
            .accessibilityLabel(category.name)
            .accessibilityAddTraits(isShown ? .isSelected : [])
            .accessibilityHint(isShown && isLastOne ? Words.Categories.keepOne : "")
            .accessibilityAction(named: Words.Categories.edit(category.name)) {
                target = CategoryTarget(kind: kind, category: category)
            }
            .accessibilityIdentifier("pick_\(category.name)")
    }

    private func toggle(_ category: TxCategory) {
        if model.book.isShown(category.id) {
            guard !isLastOne else {
                Haptics.failed()
                return
            }
            if change({ $0.hide(category.id) }) { Haptics.selected() }
        } else {
            if change({ $0.show(category.id) }) { Haptics.selected() }
        }
    }

    /// 存成了回傳 true。
    @discardableResult
    private func change(_ edit: (inout CategoryBook) -> Void) -> Bool {
        let saved = model.changeBook { book in
            edit(&book)
            return true
        }
        if !saved { saveFailed = true }
        return saved
    }
}
