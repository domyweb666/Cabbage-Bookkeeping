import Foundation

/// 待送的原話。離線時只暫存原話，連線後依序補送（規格 8.2）。
public struct PendingEntry: Codable, Identifiable, Hashable, Sendable {
    public enum State: String, Codable, Sendable {
        /// 等待送出（離線中，或排在前面的還沒送完）。
        case waiting
        /// 正在送。
        case sending
        /// 伺服器明確拒絕或暫時處理不了，留在畫面上讓使用者決定重試或刪除。
        case failed
    }

    public let id: UUID
    public let rawText: String
    public let source: String
    /// 使用者實際輸入的時間。補送時用它解析「今天」「昨天」。
    public let clientCreatedAt: Date
    public var state: State
    public var message: String?

    public init(
        id: UUID = UUID(), rawText: String, source: String, clientCreatedAt: Date,
        state: State = .waiting, message: String? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.source = source
        self.clientCreatedAt = clientCreatedAt
        self.state = state
        self.message = message
    }
}

/// 一次送出的結果。
public enum SendOutcome: Equatable, Sendable {
    /// 伺服器收下並回了結果。
    case delivered
    /// 連不上（離線、逾時）。原話留著，之後自動再送。
    case networkFailure
    /// 伺服器回了錯誤（解析失敗、達到每日上限、內容太長）。附上給使用者看的訊息。
    case rejected(String)
}

/// 待送佇列的狀態機。純邏輯，不碰網路與儲存。
public enum PendingQueue {
    /// 套用一次送出的結果。回傳 nil 代表這筆可以從佇列移除。
    public static func apply(_ outcome: SendOutcome, to entry: PendingEntry) -> PendingEntry? {
        var next = entry
        switch outcome {
        case .delivered:
            return nil
        case .networkFailure:
            next.state = .waiting
            next.message = nil
        case .rejected(let message):
            next.state = .failed
            next.message = message
        }
        return next
    }

    /// 下一筆該送的：依輸入時間先後，只送 waiting 的。離線或已有一筆在送時不送。
    public static func next(in entries: [PendingEntry], online: Bool) -> PendingEntry? {
        guard online, !entries.contains(where: { $0.state == .sending }) else { return nil }
        return entries
            .filter { $0.state == .waiting }
            .min { $0.clientCreatedAt < $1.clientCreatedAt }
    }

    /// App 重新啟動時，上次停在 sending 的視為沒送成功，改回 waiting。
    /// 重送是安全的：同一個 entry_id 後端只會處理一次。
    public static func recovered(_ entries: [PendingEntry]) -> [PendingEntry] {
        entries.map { entry in
            var e = entry
            if e.state == .sending { e.state = .waiting }
            return e
        }
    }

    /// 使用者按「重試」。
    public static func retried(_ entry: PendingEntry) -> PendingEntry {
        var e = entry
        e.state = .waiting
        e.message = nil
        return e
    }
}
