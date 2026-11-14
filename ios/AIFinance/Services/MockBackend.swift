import FinanceCore
import Foundation

/// 示範用的假後端：資料只存在記憶體，解析用很粗的規則。
/// 用在沒有設定 Supabase 的建置、SwiftUI 預覽與畫面測試，不代表真實服務的行為。
actor MockBackend: Backend {
    nonisolated let isDemo = true

    private let days = Days.taipei
    private let categories: [TxCategory]
    private var transactions: [Txn] = []
    private var rawTexts: [UUID: String] = [:]
    private var pendingDrafts: [UUID: [Draft]] = [:]
    private var profile = Profile()
    private var linked = false

    init(seeded: Bool = false) {
        let names: [(String, TxType, String)] = [
            ("飲食", .expense, "fork.knife"), ("交通", .expense, "car.fill"), ("購物", .expense, "bag.fill"),
            ("居住", .expense, "house.fill"), ("娛樂", .expense, "gamecontroller.fill"), ("醫療", .expense, "cross.case.fill"),
            ("學習", .expense, "book.fill"), ("訂閱", .expense, "repeat"), ("旅行", .expense, "airplane"),
            ("人情", .expense, "gift.fill"), ("其他支出", .expense, "ellipsis.circle.fill"), ("收入", .income, "banknote.fill"),
        ]
        let all = names.enumerated().map { i, n in
            TxCategory(id: UUID(), name: n.0, kind: n.1, icon: n.2, sortOrder: i + 1)
        }
        categories = all
        guard seeded else { return }

        let calendar = Days.taipei
        let today = calendar.day(of: Date())
        let samples: [(Int, String, String, Int, Nature?)] = [
            (65, "早餐", "飲食", -2, .routine), (500, "加油", "交通", -2, .routine),
            (4650, "機車維修", "交通", -1, .oneOff), (390, "Netflix", "訂閱", -1, .recurring),
            (120, "便當", "飲食", 0, .routine), (1280, "衣服", "購物", 0, nil),
        ]
        // 示範資料都放在本月，月初那幾天也不會跑到上個月去。
        let monthStart = calendar.monthStart(of: today)
        transactions = samples.enumerated().map { i, s in
            Txn(
                id: UUID(), type: .expense, amount: s.0,
                occurredOn: max(monthStart, calendar.adding(days: s.3, to: today)), item: s.1,
                categoryId: all.first { $0.name == s.2 }!.id, tags: [], nature: s.4,
                createdAt: String(format: "seed-%02d", i)
            )
        }
    }

    var isLinked: Bool { linked }

    private func category(_ name: String) -> TxCategory {
        categories.first { $0.name == name } ?? categories[10]
    }

    private func stamp() -> String { ISO8601DateFormatter().string(from: Date()) }

    private func guess(_ text: String) -> String? {
        let table: [(String, [String])] = [
            ("訂閱", ["netflix", "spotify", "訂閱", "icloud"]),
            ("交通", ["加油", "捷運", "公車", "計程車", "停車", "高鐵", "機車", "uber"]),
            ("醫療", ["醫生", "診所", "藥", "掛號", "牙"]),
            ("居住", ["房租", "水費", "電費", "瓦斯", "管理費"]),
            ("娛樂", ["電影", "遊戲", "ktv"]),
            ("學習", ["書", "課程"]),
            ("購物", ["衣服", "鞋", "電腦", "手機", "買"]),
            ("飲食", ["早餐", "午餐", "晚餐", "宵夜", "便當", "飲料", "咖啡", "麥當勞", "火鍋", "吃", "飯", "麵", "奶茶"]),
        ]
        let lower = text.lowercased()
        return table.first { $0.1.contains { lower.contains($0) } }?.0
    }

    func ensureSession() async throws {}

    func record(entryId: UUID, rawText: String, source: String, clientCreatedAt: String) async throws -> RecordResult {
        try? await Task.sleep(nanoseconds: 250_000_000)
        rawTexts[entryId] = rawText
        let today = days.day(of: Date())

        if rawText.hasSuffix("？") || rawText.hasSuffix("?") || rawText.contains("多少") {
            return .answer(try await ask(question: rawText))
        }

        var drafts: [Draft] = []
        for segment in rawText.split(whereSeparator: { "，,、；;。\n".contains($0) }) {
            let text = String(segment)
            let digits = text.replacingOccurrences(of: ",", with: "")
                .split(whereSeparator: { !$0.isASCII || !$0.isNumber }).compactMap { Int($0) }
            guard let amount = digits.last, amount > 0 else { continue }
            let item = text.filter { !($0.isASCII && $0.isNumber) && $0 != "," }
                .replacingOccurrences(of: "昨天", with: "").replacingOccurrences(of: "元", with: "")
                .trimmingCharacters(in: .whitespaces)
            let income = ["薪水", "獎金", "收入", "退款"].contains { text.contains($0) }
            let name = income ? "收入" : guess(text)
            var reasons: [String] = []
            if income { reasons.append("收入需要確認") }
            if amount > (profile.autoCommitMax ?? 10000) { reasons.append("金額超過 \(Money.grouped(profile.autoCommitMax ?? 10000))") }
            if name == nil { reasons.append("分類不確定") }
            if !profile.autoCommit { reasons.append("已關閉直接入帳") }
            drafts.append(Draft(
                type: income ? .income : .expense, amount: amount,
                occurredOn: text.contains("昨天") ? days.adding(days: -1, to: today) : today,
                item: item.isEmpty ? "消費" : item, categoryId: name.map { category($0).id }, categoryName: name,
                reasons: reasons
            ))
        }

        if drafts.isEmpty { return .unclear("要記多少錢？請補上金額，例如「午餐 120」。") }
        if drafts.contains(where: { !$0.reasons.isEmpty }) {
            pendingDrafts[entryId] = drafts
            return .needsConfirm(drafts)
        }
        return .committed(insert(drafts, entryId: entryId, source: "ai"))
    }

    private func insert(_ drafts: [Draft], entryId: UUID, source: String) -> [Txn] {
        let rows = drafts.map { d in
            Txn(id: UUID(), entryId: entryId, type: d.type, amount: d.amount, occurredOn: d.occurredOn, item: d.item,
                merchant: d.merchant, categoryId: d.categoryId ?? category("其他支出").id, categorySource: source,
                tags: d.tags, nature: d.nature, createdAt: stamp())
        }
        transactions += rows
        return rows
    }

    func confirm(entryId: UUID, drafts: [Draft]) async throws -> RecordResult {
        pendingDrafts[entryId] = nil
        return .committed(insert(drafts, entryId: entryId, source: "user"))
    }

    func cancelConfirm(entryId: UUID) async throws {
        pendingDrafts[entryId] = nil
    }

    func ask(question: String) async throws -> AskAnswer {
        let today = days.day(of: Date())
        let month = String(today.prefix(7))
        let rows = transactions.filter { $0.deletedAt == nil && $0.type == .expense && $0.occurredOn.hasPrefix(month) }
        let total = rows.reduce(0) { $0 + $1.amount }
        let answer = rows.isEmpty
            ? "這個月還沒有支出紀錄。"
            : "這個月到目前支出共 \(Money.format(total))，一共 \(rows.count) 筆。"
        return AskAnswer(answer: answer, evidence: [
            Evidence(tool: "sum_transactions", count: rows.count, total: total, transactionIds: rows.map(\.id)),
        ])
    }

    func fetchCategories() async throws -> [TxCategory] { categories }

    func fetchTransactions() async throws -> [Txn] { transactions.filter { $0.deletedAt == nil } }

    func createTransaction(_ fields: TxnFields) async throws -> Txn {
        let row = Txn(
            id: UUID(), type: fields.type, amount: fields.amount, occurredOn: fields.occurredOn, item: fields.item,
            merchant: fields.merchant, categoryId: fields.categoryId, categorySource: fields.categorySource,
            tags: fields.tags, nature: fields.nature, note: fields.note, createdAt: stamp()
        )
        transactions.append(row)
        return row
    }

    func updateTransaction(id: UUID, fields: TxnFields) async throws -> Txn {
        guard let i = transactions.firstIndex(where: { $0.id == id }) else {
            throw BackendError.server(code: "not_found", message: "找不到這筆紀錄，可能已經被刪除。")
        }
        var row = transactions[i]
        row.type = fields.type
        row.amount = fields.amount
        row.occurredOn = fields.occurredOn
        row.item = fields.item
        row.merchant = fields.merchant
        row.categoryId = fields.categoryId
        row.categorySource = fields.categorySource
        row.tags = fields.tags
        row.nature = fields.nature
        row.note = fields.note
        transactions[i] = row
        return row
    }

    func setDeleted(id: UUID, deleted: Bool) async throws {
        guard let i = transactions.firstIndex(where: { $0.id == id }) else { return }
        transactions[i].deletedAt = deleted ? stamp() : nil
    }

    func fetchRawText(entryId: UUID) async throws -> String? { rawTexts[entryId] }

    func monthlyOverview(monthOf day: String) async throws -> MonthlyOverview {
        let month = String(day.prefix(7))
        let rows = transactions.filter { $0.deletedAt == nil && $0.occurredOn.hasPrefix(month) }
        let expenses = rows.filter { $0.type == .expense }
        let oneOff = expenses.filter { $0.nature == .oneOff }.reduce(0) { $0 + $1.amount }
        let total = expenses.reduce(0) { $0 + $1.amount }
        let byCategory = Dictionary(grouping: expenses, by: \.categoryId).compactMap { id, items -> CategoryTotal? in
            guard let c = categories.first(where: { $0.id == id }) else { return nil }
            return CategoryTotal(categoryId: id, name: c.name, icon: c.icon, total: items.reduce(0) { $0 + $1.amount }, count: items.count)
        }.sorted { $0.total > $1.total }
        return MonthlyOverview(
            month: month, totalExpense: total,
            totalIncome: rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount },
            routineExpense: total - oneOff, oneOffExpense: oneOff, transactionCount: rows.count, byCategory: byCategory
        )
    }

    func fetchProfile() async throws -> Profile { profile }

    func updateProfile(_ profile: Profile) async throws { self.profile = profile }

    func deleteAllData() async throws {
        transactions = []
        rawTexts = [:]
        pendingDrafts = [:]
        profile = Profile()
    }

    func linkApple(idToken: String, rawNonce: String, allowSwitch: Bool) async throws -> Bool {
        linked = true
        return false
    }
}
