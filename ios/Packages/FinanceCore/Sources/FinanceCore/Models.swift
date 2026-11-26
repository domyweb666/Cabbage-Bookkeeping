import Foundation

// 型別名稱刻意避開 Category、Transaction，免得跟 ObjectiveC、SwiftUI 的同名型別打架。

public enum TxType: String, Codable, CaseIterable, Sendable {
    case expense
    case income

    public var label: String { self == .expense ? "支出" : "收入" }
}

/// 一筆紀錄被改之前的樣子。修改不覆蓋掉原值。
public struct TxnRevision: Codable, Hashable, Sendable {
    public let replacedAt: Date
    public let type: TxType
    public let amount: Int
    public let occurredOn: String
    public let categoryId: UUID
    public let isOneOff: Bool
}

/// 使用者在記帳畫面填的內容。
public struct TxnFields: Hashable, Sendable {
    public var type: TxType
    public var amount: Int
    public var occurredOn: String
    public var categoryId: UUID
    public var note: String
    public var isOneOff: Bool

    public init(
        type: TxType, amount: Int, occurredOn: String, categoryId: UUID, note: String = "", isOneOff: Bool = false
    ) {
        self.type = type
        self.amount = amount
        self.occurredOn = occurredOn
        self.categoryId = categoryId
        self.note = note
        self.isOneOff = isOneOff
    }
}

/// 一筆紀錄。金額是正整數（新台幣元），日期是使用者選的 yyyy-MM-dd。
public struct Txn: Codable, Identifiable, Hashable, Sendable {
    /// 2：多了 fixed 和 estimate。
    /// 3：多了 ledgerId（哪一本帳）。舊的沒有這欄，讀出來是 nil，算「我的帳本」，不用搬資料。
    public static let currentSchema = 3

    public let id: UUID
    public private(set) var type: TxType
    public private(set) var amount: Int
    public private(set) var occurredOn: String
    public private(set) var categoryId: UUID
    public private(set) var note: String
    /// 一次性的支出：總額照算，跟平常比的時候不算。
    public private(set) var isOneOff: Bool
    public let createdAt: Date
    /// 記下這筆時的時區。
    public let timeZone: String
    public var deletedAt: Date?
    public private(set) var revisions: [TxnRevision]
    /// 哪一項固定支出自動記的。手動記的是 nil。
    public let fixed: FixedOrigin?
    /// 補的是哪幾天的大概。照實記的是 nil。
    public private(set) var estimate: DayRange?
    /// 哪一本帳。nil 是「我的帳本」（多帳本以前記的）。改一筆不會換本。
    public let ledgerId: UUID?
    public let schemaVersion: Int

    public init(
        id: UUID = UUID(), fields: TxnFields, createdAt: Date, timeZone: String,
        fixed: FixedOrigin? = nil, estimate: DayRange? = nil, ledgerId: UUID? = nil
    ) {
        self.id = id
        self.type = fields.type
        self.amount = fields.amount
        self.occurredOn = fields.occurredOn
        self.categoryId = fields.categoryId
        self.note = fields.note
        self.isOneOff = fields.type == .expense && fields.isOneOff
        self.createdAt = createdAt
        self.timeZone = timeZone
        self.deletedAt = nil
        self.revisions = []
        self.fixed = fixed
        self.estimate = fields.type == .expense ? estimate : nil
        self.ledgerId = ledgerId
        self.schemaVersion = Self.currentSchema
    }

    public var fields: TxnFields {
        TxnFields(
            type: type, amount: amount, occurredOn: occurredOn, categoryId: categoryId, note: note, isOneOff: isOneOff
        )
    }

    /// 套用修改。會影響數字的欄位有變，就把原值留在 revisions。
    public func applying(_ new: TxnFields, at date: Date) -> Txn {
        var copy = self
        let oneOff = new.type == .expense && new.isOneOff
        let changed = new.type != type || new.amount != amount || new.occurredOn != occurredOn
            || new.categoryId != categoryId || oneOff != isOneOff
        if changed {
            copy.revisions.append(TxnRevision(
                replacedAt: date, type: type, amount: amount, occurredOn: occurredOn,
                categoryId: categoryId, isOneOff: isOneOff
            ))
        }
        copy.type = new.type
        copy.amount = new.amount
        copy.occurredOn = new.occurredOn
        copy.categoryId = new.categoryId
        copy.note = new.note
        copy.isOneOff = oneOff
        // 改成收入，或日期搬到那幾天以外，就不再是那幾天的大概。
        if new.type != .expense || estimate?.contains(new.occurredOn) == false { copy.estimate = nil }
        return copy
    }

    /// 這個月算到第幾天為止的金額。大概的數字照天數分。nil 代表算整個月。
    func amount(throughDay cutoff: Int?) -> Int {
        guard let cutoff, let estimate else { return amount }
        let from = Days.number(of: estimate.from)
        let to = Days.number(of: estimate.to)
        if to <= cutoff { return amount }
        if from > cutoff { return 0 }
        return amount * (cutoff - from + 1) / (to - from + 1)
    }
}

/// 每月預算。每改一次新增一筆，舊的月份繼續用當時的數字。
public struct Budget: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    /// 從哪個月開始生效（yyyy-MM-01）。
    public let month: String
    /// 0 代表從這個月起不訂預算。
    public let amount: Int
    public let createdAt: Date
    /// 哪一本帳的預算。nil 是「我的帳本」（多帳本以前訂的，舊資料沒有這欄）。
    public let ledgerId: UUID?

    public init(id: UUID = UUID(), month: String, amount: Int, createdAt: Date, ledgerId: UUID? = nil) {
        self.id = id
        self.month = month
        self.amount = amount
        self.createdAt = createdAt
        self.ledgerId = ledgerId
    }

    /// 某個月適用的預算，沒訂就是 nil。
    public static func amount(for month: String, in budgets: [Budget]) -> Int? {
        let latest = budgets
            .filter { $0.month <= month }
            .max { ($0.month, $0.createdAt) < ($1.month, $1.createdAt) }
        guard let latest, latest.amount > 0 else { return nil }
        return latest.amount
    }
}
