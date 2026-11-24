import Foundation

/// 使用者自己新增的分類。刪除是標記 deletedAt，記過的紀錄照樣看得到名字。
public struct CustomCategory: Codable, Identifiable, Hashable, Sendable {
    public static let currentSchema = 1

    public let id: UUID
    public let type: TxType
    public fileprivate(set) var name: String
    public fileprivate(set) var icon: String
    public let createdAt: Date
    public fileprivate(set) var deletedAt: Date?
    public let schemaVersion: Int

    init(id: UUID, type: TxType, name: String, icon: String, createdAt: Date) {
        self.id = id
        self.type = type
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.deletedAt = nil
        self.schemaVersion = Self.currentSchema
    }

    fileprivate var category: TxCategory {
        TxCategory(number: nil, id: id, name: name, kind: type, group: Categories.customGroup, icon: icon)
    }
}

/// 內建分類被改過的名字和圖示。編號不變。
struct CategoryOverride: Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let icon: String
}

public enum CategoryNameProblem: Hashable, Sendable {
    case empty
    case tooLong
    case duplicate
}

/// 這支手機的分類：內建的、改過的名字、自己新增的、記帳畫面顯示哪些、照什麼順序。
/// 純值，整份存成一段 JSON。名字和圖示都在這裡找，改了所有地方一起變。
public struct CategoryBook: Codable, Hashable, Sendable {
    public static let currentSchema = 1
    public static let maxNameLength = 8

    public private(set) var schemaVersion = CategoryBook.currentSchema
    private var customs: [CustomCategory] = []
    private var overrides: [CategoryOverride] = []
    private var shownExpense: [UUID] = CategoryBook.standardIDs(.expense)
    private var shownIncome: [UUID] = CategoryBook.standardIDs(.income)

    /// 沒動過設定的樣子。
    public init() {}

    /// 讀回來的資料先清過：不認得的、重複的、已刪的、放錯邊的編號都拿掉，一個都不剩就回到預設。
    public func cleaned() -> CategoryBook {
        var copy = self
        for kind in TxType.allCases {
            var seen = Set<UUID>()
            let kept = shownIDs(kind).filter { id in
                guard let category = find(id), category.kind == kind, !isDeleted(id) else { return false }
                return seen.insert(id).inserted
            }
            copy.setShown(kept.isEmpty ? Self.standardIDs(kind) : kept, kind)
        }
        return copy
    }

    // MARK: - 找

    /// 照編號找，刪掉的自訂分類也找得到。
    public func find(_ id: UUID?) -> TxCategory? {
        guard let id else { return nil }
        if let custom = customs.first(where: { $0.id == id }) { return custom.category }
        return Categories.find(id).map { applyingOverride($0) }
    }

    /// 一筆紀錄的分類。找不到就算在「其他」，不能因為找不到就漏算。
    public func category(of row: Txn) -> TxCategory {
        find(row.categoryId) ?? applyingOverride(Categories.fallback(row.type))
    }

    /// 清單上的標題：有備註用備註，沒有就用分類名。
    public func title(of row: Txn) -> String {
        row.note.isEmpty ? category(of: row).name : row.note
    }

    /// 記帳畫面顯示的，照使用者排的順序。
    public func shown(of kind: TxType) -> [TxCategory] {
        shownIDs(kind).compactMap { find($0) }
    }

    /// 記帳畫面的格子。改舊紀錄時，那一筆的分類沒顯示（或已刪掉）也要補在最後。
    public func choices(_ kind: TxType, keeping original: UUID? = nil) -> [TxCategory] {
        let items = shown(of: kind)
        guard let extra = find(original), extra.kind == kind, !items.contains(where: { $0.id == extra.id }) else {
            return items
        }
        return items + [extra]
    }

    /// 選好的分類還在格子上就留著，不在就是 nil。
    public func selection(_ selected: UUID?, kind: TxType, keeping original: UUID? = nil) -> UUID? {
        choices(kind, keeping: original).first { $0.id == selected }?.id
    }

    /// 沒顯示的，照分組。自己新增的放最前面一組。
    public func hiddenGroups(_ kind: TxType) -> [CategoryGroup] {
        let shown = Set(shownIDs(kind))
        let own = customs.filter { $0.type == kind && $0.deletedAt == nil && !shown.contains($0.id) }.map(\.category)
        let builtIn = Categories.groups(kind).map { group in
            CategoryGroup(
                name: group.name, items: group.items.filter { !shown.contains($0.id) }.map { applyingOverride($0) }
            )
        }
        return ([CategoryGroup(name: Categories.customGroup, items: own)] + builtIn).filter { !$0.items.isEmpty }
    }

    public func isShown(_ id: UUID) -> Bool {
        shownExpense.contains(id) || shownIncome.contains(id)
    }

    public func isCustom(_ id: UUID) -> Bool {
        customs.contains { $0.id == id }
    }

    /// 內建分類的名字或圖示被改過。
    public func isRenamed(_ id: UUID) -> Bool {
        overrides.contains { $0.id == id }
    }

    public func isDeleted(_ id: UUID) -> Bool {
        customs.contains { $0.id == id && $0.deletedAt != nil }
    }

    // MARK: - 顯示與順序

    /// 加到顯示的最後面。
    public mutating func show(_ id: UUID) {
        guard let category = find(id), !isShown(id), !isDeleted(id) else { return }
        setShown(shownIDs(category.kind) + [id], category.kind)
    }

    /// 不顯示。每一邊至少留一個，最後一個拿不掉，回傳 false。
    @discardableResult
    public mutating func hide(_ id: UUID) -> Bool {
        guard let category = find(id) else { return false }
        let left = shownIDs(category.kind).filter { $0 != id }
        guard !left.isEmpty else { return false }
        setShown(left, category.kind)
        return true
    }

    /// 拖曳排序。參數的意思跟 SwiftUI 的 onMove 一樣：to 是搬之前的位置。
    public mutating func move(_ kind: TxType, from offsets: IndexSet, to target: Int) {
        var list = shownIDs(kind)
        let picked = offsets.filter { list.indices.contains($0) }.sorted()
        let moving = picked.map { list[$0] }
        for index in picked.reversed() { list.remove(at: index) }
        let place = target - picked.filter { $0 < target }.count
        list.insert(contentsOf: moving, at: min(max(0, place), list.count))
        setShown(list, kind)
    }

    /// 往前（-1）或往後（1）移一格。到頭了就不動，回傳 false。
    @discardableResult
    public mutating func shift(_ id: UUID, by step: Int) -> Bool {
        guard canShift(id, by: step), let category = find(id) else { return false }
        var list = shownIDs(category.kind)
        guard let index = list.firstIndex(of: id) else { return false }
        list.swapAt(index, index + step)
        setShown(list, category.kind)
        return true
    }

    public func canShift(_ id: UUID, by step: Int) -> Bool {
        guard let category = find(id) else { return false }
        let list = shownIDs(category.kind)
        guard let index = list.firstIndex(of: id) else { return false }
        return list.indices.contains(index + step)
    }

    /// 某一邊恢復預設：顯示哪些、順序、內建的名字與圖示。自己新增的不刪，變成沒顯示。
    public mutating func reset(_ kind: TxType) {
        setShown(Self.standardIDs(kind), kind)
        overrides.removeAll { Categories.find($0.id)?.kind == kind }
    }

    public func isStandard(_ kind: TxType) -> Bool {
        shownIDs(kind) == Self.standardIDs(kind) && !overrides.contains { Categories.find($0.id)?.kind == kind }
    }

    // MARK: - 取名

    /// 名字能不能用。同一邊還在用的不能同名；內建的原名也留著，恢復的時候才不會撞名。
    public func problem(with name: String, kind: TxType, excluding id: UUID? = nil) -> CategoryNameProblem? {
        let trimmed = Self.trimmed(name)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > Self.maxNameLength { return .tooLong }
        let builtIn = Categories.of(kind).filter { $0.id != id }
        let own = customs.filter { $0.type == kind && $0.deletedAt == nil && $0.id != id }
        let taken = builtIn.map(\.name) + builtIn.map { applyingOverride($0).name } + own.map(\.name)
        return taken.contains(trimmed) ? .duplicate : nil
    }

    /// 新增自己的分類，加到顯示的最後面。名字不能用就不加，回傳 false。
    public mutating func add(_ name: String, icon: String, kind: TxType, id: UUID = UUID(), at date: Date) -> Bool {
        guard problem(with: name, kind: kind) == nil else { return false }
        customs.append(CustomCategory(id: id, type: kind, name: Self.trimmed(name), icon: icon, createdAt: date))
        show(id)
        return true
    }

    /// 改名字和圖示，順便往前（負）或往後（正）移幾格。內建的存成覆蓋，改回原樣就把覆蓋拿掉。
    public mutating func edit(_ id: UUID, name: String, icon: String, moved: Int = 0) -> Bool {
        guard let category = find(id), problem(with: name, kind: category.kind, excluding: id) == nil else { return false }
        // 一格一格移，到頭了就停。
        for _ in 0..<abs(moved) { shift(id, by: moved.signum()) }
        let trimmed = Self.trimmed(name)
        if let index = customs.firstIndex(where: { $0.id == id }) {
            customs[index].name = trimmed
            customs[index].icon = icon
            return true
        }
        restoreOriginal(id)
        if let original = Categories.find(id), original.name != trimmed || original.icon != icon {
            overrides.append(CategoryOverride(id: id, name: trimmed, icon: icon))
        }
        return true
    }

    /// 內建分類恢復原本的名字與圖示。
    public mutating func restoreOriginal(_ id: UUID) {
        overrides.removeAll { $0.id == id }
    }

    /// 刪掉自己新增的分類（標記）。內建的不能刪；是顯示中的最後一個也不能刪。
    public mutating func delete(_ id: UUID, at date: Date) -> Bool {
        guard let index = customs.firstIndex(where: { $0.id == id }) else { return false }
        if isShown(id), !hide(id) { return false }
        customs[index].deletedAt = date
        return true
    }

    // MARK: - 小工具

    private func shownIDs(_ kind: TxType) -> [UUID] {
        kind == .expense ? shownExpense : shownIncome
    }

    private mutating func setShown(_ ids: [UUID], _ kind: TxType) {
        if kind == .expense { shownExpense = ids } else { shownIncome = ids }
    }

    private func applyingOverride(_ category: TxCategory) -> TxCategory {
        guard let change = overrides.first(where: { $0.id == category.id }) else { return category }
        return TxCategory(
            number: category.number, id: category.id, name: change.name, kind: category.kind,
            group: category.group, icon: change.icon
        )
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func standardIDs(_ kind: TxType) -> [UUID] {
        Categories.of(kind).filter { $0.isStandard }.map(\.id)
    }
}
