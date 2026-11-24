import Foundation

// 型別名稱刻意避開 Category、Transaction，免得跟 ObjectiveC、SwiftUI 的同名型別打架。

public enum TxType: String, Codable, CaseIterable, Sendable {
    case expense
    case income

    public var label: String { self == .expense ? "支出" : "收入" }
}

public struct TxCategory: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: TxType
    public let icon: String
}

/// 內建分類。編號固定不變，紀錄靠編號引用，改名不會影響舊紀錄。
public enum Categories {
    public static let all: [TxCategory] = [
        make(1, "飲食", .expense, "fork.knife"),
        make(2, "交通", .expense, "car.fill"),
        make(3, "購物", .expense, "bag.fill"),
        make(4, "日用", .expense, "basket.fill"),
        make(5, "居住", .expense, "house.fill"),
        make(6, "娛樂", .expense, "gamecontroller.fill"),
        make(7, "醫療", .expense, "cross.case.fill"),
        make(8, "學習", .expense, "book.fill"),
        make(9, "訂閱", .expense, "repeat"),
        make(10, "旅行", .expense, "airplane"),
        make(11, "人情", .expense, "gift.fill"),
        make(12, "其他", .expense, "ellipsis.circle.fill"),
        make(21, "薪水", .income, "banknote.fill"),
        make(22, "獎金", .income, "star.fill"),
        make(23, "投資", .income, "chart.line.uptrend.xyaxis"),
        make(24, "其他收入", .income, "ellipsis.circle.fill"),
    ]

    public static func of(_ kind: TxType) -> [TxCategory] {
        all.filter { $0.kind == kind }
    }

    public static func find(_ id: UUID?) -> TxCategory? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// 測試與示範資料用：照名字找。
    public static func named(_ name: String) -> TxCategory {
        all.first { $0.name == name }!
    }

    private static func make(_ number: Int, _ name: String, _ kind: TxType, _ icon: String) -> TxCategory {
        let id = UUID(uuidString: String(format: "BA1CA100-0000-4000-8000-%012d", number))!
        return TxCategory(id: id, name: name, kind: kind, icon: icon)
    }
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
    public static let currentSchema = 1

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
    public let schemaVersion: Int

    public init(id: UUID = UUID(), fields: TxnFields, createdAt: Date, timeZone: String) {
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
        return copy
    }

    public var category: TxCategory? { Categories.find(categoryId) }

    /// 清單上的標題：有備註用備註，沒有就用分類名。
    public var title: String { note.isEmpty ? (category?.name ?? "其他") : note }
}

/// 每月預算。每改一次新增一筆，舊的月份繼續用當時的數字。
public struct Budget: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    /// 從哪個月開始生效（yyyy-MM-01）。
    public let month: String
    /// 0 代表從這個月起不訂預算。
    public let amount: Int
    public let createdAt: Date

    public init(id: UUID = UUID(), month: String, amount: Int, createdAt: Date) {
        self.id = id
        self.month = month
        self.amount = amount
        self.createdAt = createdAt
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
