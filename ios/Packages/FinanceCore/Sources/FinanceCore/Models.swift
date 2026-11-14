import Foundation

// 與後端共用的資料形狀。JSON 一律用 snake_case，解碼時轉成 camelCase（見 JSONCoding）。
// 型別名稱刻意避開 Category、Transaction，免得跟 ObjectiveC、SwiftUI 的同名型別打架。

public enum TxType: String, Codable, CaseIterable, Sendable {
    case expense
    case income

    public var label: String { self == .expense ? "支出" : "收入" }
}

public enum Nature: String, Codable, CaseIterable, Sendable {
    case routine
    case oneOff = "one_off"
    case recurring

    public var label: String {
        switch self {
        case .routine: return "日常"
        case .oneOff: return "一次性"
        case .recurring: return "固定"
        }
    }
}

public struct TxCategory: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: TxType
    public let icon: String
    public let sortOrder: Int

    public init(id: UUID, name: String, kind: TxType, icon: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.sortOrder = sortOrder
    }
}

/// 一筆交易。金額是正整數（新台幣元），日期是使用者時區的 yyyy-MM-dd。
public struct Txn: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var entryId: UUID?
    public var type: TxType
    public var amount: Int
    public var occurredOn: String
    public var item: String
    public var merchant: String?
    public var categoryId: UUID
    public var categorySource: String
    public var tags: [String]
    public var nature: Nature?
    public var paymentMethod: String?
    public var note: String?
    public var createdAt: String?
    public var deletedAt: String?

    public init(
        id: UUID, entryId: UUID? = nil, type: TxType, amount: Int, occurredOn: String, item: String,
        merchant: String? = nil, categoryId: UUID, categorySource: String = "ai", tags: [String] = [],
        nature: Nature? = nil, paymentMethod: String? = nil, note: String? = nil,
        createdAt: String? = nil, deletedAt: String? = nil
    ) {
        self.id = id
        self.entryId = entryId
        self.type = type
        self.amount = amount
        self.occurredOn = occurredOn
        self.item = item
        self.merchant = merchant
        self.categoryId = categoryId
        self.categorySource = categorySource
        self.tags = tags
        self.nature = nature
        self.paymentMethod = paymentMethod
        self.note = note
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

/// 等使用者確認的草稿。reasons 說明為什麼沒有直接入帳。
public struct Draft: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var type: TxType
    public var amount: Int
    public var occurredOn: String
    public var item: String
    public var merchant: String?
    public var categoryId: UUID?
    public var categoryName: String?
    public var tags: [String]
    public var nature: Nature?
    public var paymentMethod: String?
    public var reasons: [String]

    enum CodingKeys: String, CodingKey {
        case type, amount, occurredOn, item, merchant, categoryId, categoryName, tags, nature, paymentMethod, reasons
    }

    public init(
        type: TxType, amount: Int, occurredOn: String, item: String, merchant: String? = nil,
        categoryId: UUID? = nil, categoryName: String? = nil, tags: [String] = [], nature: Nature? = nil,
        paymentMethod: String? = nil, reasons: [String] = []
    ) {
        self.type = type
        self.amount = amount
        self.occurredOn = occurredOn
        self.item = item
        self.merchant = merchant
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.tags = tags
        self.nature = nature
        self.paymentMethod = paymentMethod
        self.reasons = reasons
    }

    /// 送出前的檢查。回傳空陣列代表可以送。
    public func problems(today: String) -> [String] {
        var out: [String] = []
        if amount <= 0 { out.append("金額要大於 0") }
        if item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("需要填品項") }
        if categoryId == nil { out.append("需要選分類") }
        if occurredOn > today { out.append("日期不能在未來") }
        return out
    }
}

public struct Evidence: Codable, Hashable, Sendable {
    public let tool: String
    public let count: Int
    public let total: Int
    public let transactionIds: [UUID]

    public init(tool: String, count: Int, total: Int, transactionIds: [UUID]) {
        self.tool = tool
        self.count = count
        self.total = total
        self.transactionIds = transactionIds
    }
}

public struct AskAnswer: Codable, Hashable, Sendable {
    public let answer: String
    public let evidence: [Evidence]

    public init(answer: String, evidence: [Evidence]) {
        self.answer = answer
        self.evidence = evidence
    }

    /// 依據的筆數與交易（跨多個工具呼叫時去重複）。
    public var evidenceIds: [UUID] {
        var seen = Set<UUID>()
        return evidence.flatMap(\.transactionIds).filter { seen.insert($0).inserted }
    }

    public var evidenceCount: Int {
        let ids = evidenceIds.count
        return ids > 0 ? ids : (evidence.map(\.count).max() ?? 0)
    }
}

/// POST /record 的四種結果，加上取消確認。
public enum RecordResult: Decodable, Sendable {
    case committed([Txn])
    case needsConfirm([Draft])
    case answer(AskAnswer)
    case unclear(String)
    case cancelled

    enum CodingKeys: String, CodingKey {
        case result, transactions, drafts, message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .result)
        switch kind {
        case "committed":
            self = .committed(try c.decode([Txn].self, forKey: .transactions))
        case "needs_confirm":
            self = .needsConfirm(try c.decode([Draft].self, forKey: .drafts))
        case "answer":
            self = .answer(try AskAnswer(from: decoder))
        case "unclear":
            self = .unclear(try c.decodeIfPresent(String.self, forKey: .message) ?? "看不太懂這句，可以補上金額再試一次。")
        case "cancelled":
            self = .cancelled
        default:
            throw DecodingError.dataCorruptedError(forKey: .result, in: c, debugDescription: "未知的 result：\(kind)")
        }
    }
}

public struct CategoryTotal: Codable, Identifiable, Hashable, Sendable {
    public let categoryId: UUID
    public let name: String
    public let icon: String
    public let total: Int
    public let count: Int

    public var id: UUID { categoryId }

    public init(categoryId: UUID, name: String, icon: String, total: Int, count: Int) {
        self.categoryId = categoryId
        self.name = name
        self.icon = icon
        self.total = total
        self.count = count
    }
}

public struct MonthlyOverview: Codable, Hashable, Sendable {
    public let month: String
    public let totalExpense: Int
    public let totalIncome: Int
    public let routineExpense: Int
    public let oneOffExpense: Int
    public let transactionCount: Int
    public let byCategory: [CategoryTotal]

    public init(
        month: String, totalExpense: Int, totalIncome: Int, routineExpense: Int, oneOffExpense: Int,
        transactionCount: Int, byCategory: [CategoryTotal]
    ) {
        self.month = month
        self.totalExpense = totalExpense
        self.totalIncome = totalIncome
        self.routineExpense = routineExpense
        self.oneOffExpense = oneOffExpense
        self.transactionCount = transactionCount
        self.byCategory = byCategory
    }
}

public struct Profile: Codable, Hashable, Sendable {
    public var autoCommit: Bool
    public var autoCommitMax: Int?

    public init(autoCommit: Bool = true, autoCommitMax: Int? = nil) {
        self.autoCommit = autoCommit
        self.autoCommitMax = autoCommitMax
    }
}

public struct APIErrorBody: Codable, Hashable, Sendable {
    public let code: String
    public let message: String
}

/// 後端統一回傳格式：{ success, data, error, request_id }
public struct APIEnvelope<T: Decodable>: Decodable {
    public let success: Bool
    public let data: T?
    public let error: APIErrorBody?
    public let requestId: String?
}

public enum JSONCoding {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
