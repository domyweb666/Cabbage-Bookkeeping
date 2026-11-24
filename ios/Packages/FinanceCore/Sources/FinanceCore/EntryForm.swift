import Foundation

/// 記一筆畫面上填的內容。打開時留一份，之後跟它比就知道動過沒有。
public struct EntryForm: Hashable, Sendable {
    public static let maxNoteLength = 100

    public let type: TxType
    public let amount: Int
    public let occurredOn: String
    /// nil 代表還沒選分類。
    public let categoryId: UUID?
    public let note: String
    public let isOneOff: Bool

    public init(type: TxType, amount: Int, occurredOn: String, categoryId: UUID?, note: String, isOneOff: Bool) {
        self.type = type
        self.amount = amount
        self.occurredOn = occurredOn
        self.categoryId = categoryId
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNoteLength))
        self.isOneOff = type == .expense && isOneOff
    }

    /// 剛打開「記一筆」的樣子。
    public init(today: String) {
        self.init(type: .expense, amount: 0, occurredOn: today, categoryId: nil, note: "", isOneOff: false)
    }

    /// 剛打開一筆舊紀錄的樣子。分類在格子上找不到就當作還沒選，要先選一個才能記下。
    public init(editing row: Txn, book: CategoryBook) {
        self.init(
            type: row.type,
            amount: row.amount,
            occurredOn: row.occurredOn,
            categoryId: book.selection(row.categoryId, kind: row.type, keeping: row.categoryId),
            note: row.note,
            isOneOff: row.isOneOff
        )
    }

    /// 可以記下的內容。金額或分類還沒填是 nil。
    public var fields: TxnFields? {
        guard amount > 0, let categoryId else { return nil }
        return TxnFields(
            type: type, amount: amount, occurredOn: occurredOn, categoryId: categoryId, note: note, isOneOff: isOneOff
        )
    }
}
