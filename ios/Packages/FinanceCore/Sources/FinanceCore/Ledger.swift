import Foundation

// 帳本：紀錄、預算、固定支出、存錢每本分開；常用分類（CategoryBook）大家共用。
// 之後 iCloud 共享會一本一本共享，所以帳本的編號一建好就不換，每筆紀錄都帶著它屬於哪一本。

/// 帳本的顏色。存的是名字，畫面再對到 Theme 的顏色，以後換色票不用搬資料。
public enum LedgerColor: String, Codable, CaseIterable, Sendable {
    case plum, terracotta, blue, olive, violet, green
}

public struct Ledger: Codable, Identifiable, Hashable, Sendable {
    public static let currentSchema = 1
    /// 「我的帳本」：多帳本以前的紀錄都在這本。編號固定，舊紀錄的 ledgerId 是 nil 也算這本。
    public static let mainID = UUID(uuid: (0xBA, 0x1C, 0xA1, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x01))
    public static let mainName = "我的帳本"
    public static let maxNameLength = 12

    public let id: UUID
    public private(set) var name: String
    public private(set) var color: LedgerColor
    public let createdAt: Date
    /// 刪掉的那一刻。刪掉的帳本留著，裡面的紀錄才找得到自己屬於哪一本。
    public var deletedAt: Date?
    public let schemaVersion: Int

    public init(id: UUID = UUID(), name: String, color: LedgerColor, createdAt: Date) {
        self.id = id
        self.name = Self.clean(name)
        self.color = color
        self.createdAt = createdAt
        self.deletedAt = nil
        self.schemaVersion = Self.currentSchema
    }

    /// 還沒改過名字時的「我的帳本」。不用存，讀的時候補上。
    public static let main = Ledger(
        id: mainID, name: mainName, color: .plum, createdAt: Date(timeIntervalSince1970: 0)
    )

    public var isMain: Bool { id == Self.mainID }

    public func renamed(_ name: String, color: LedgerColor) -> Ledger {
        var copy = self
        copy.name = Self.clean(name)
        copy.color = color
        return copy
    }

    /// 前後空白拿掉，太長的截掉。
    public static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }
}

/// 帶著帳本編號的資料：紀錄、預算、固定支出、存錢。
public protocol LedgerOwned {
    /// nil 是「我的帳本」（多帳本以前的資料沒有這欄）。
    var ledgerId: UUID? { get }
}

extension LedgerOwned {
    /// 屬於哪一本。nil 算「我的帳本」。
    public var ledgerKey: UUID { ledgerId ?? Ledger.mainID }

    public func belongs(to ledger: UUID) -> Bool { ledgerKey == ledger }
}

extension Txn: LedgerOwned {}
extension Budget: LedgerOwned {}
extension FixedExpense: LedgerOwned {}

public enum Ledgers {
    /// 還在用的帳本，「我的帳本」在最前面，其他照建立的先後。沒存過「我的帳本」就補上預設的。
    public static func alive(_ saved: [Ledger]) -> [Ledger] {
        var all = saved
        if !all.contains(where: \.isMain) { all.append(.main) }
        return all.filter { $0.deletedAt == nil }
            .sorted { ($0.isMain ? 0 : 1, $0.createdAt) < ($1.isMain ? 0 : 1, $1.createdAt) }
    }

    /// 帳本的名字。找不到（例如資料壞了）就算「我的帳本」。
    public static func name(of id: UUID, in saved: [Ledger]) -> String {
        saved.first { $0.id == id }?.name ?? Ledger.mainName
    }

    public enum Problem: Equatable, Sendable {
        case empty
        case duplicate
    }

    /// 名字能不能用：空的不行，跟還在用的另一本同名不行。
    public static func problem(with name: String, in saved: [Ledger], excluding id: UUID? = nil) -> Problem? {
        let cleaned = Ledger.clean(name)
        if cleaned.isEmpty { return .empty }
        if alive(saved).contains(where: { $0.id != id && $0.name == cleaned }) { return .duplicate }
        return nil
    }
}
