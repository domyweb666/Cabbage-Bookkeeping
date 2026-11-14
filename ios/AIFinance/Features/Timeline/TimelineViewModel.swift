import FinanceCore
import Foundation
import Observation

/// 等使用者確認的一組草稿。
struct ConfirmRequest: Identifiable, Hashable {
    let id: UUID
    let rawText: String
    var drafts: [Draft]
}

/// 底部的提示條：「已記錄　復原」「已刪除　復原」。
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// 按下復原時要軟刪除的交易（剛入帳的）。
    var undoCommitted: [Txn] = []
    /// 按下復原時要救回來的交易（剛刪除的）。
    var undoDeleted: Txn?

    var canUndo: Bool { !undoCommitted.isEmpty || undoDeleted != nil }
}

/// 主畫面的狀態與動作：時間軸、輸入、待送佇列、確認、回答、復原。
@MainActor
@Observable
final class TimelineViewModel {
    private(set) var transactions: [Txn] = []
    private(set) var categories: [TxCategory] = []
    private(set) var pending: [PendingEntry] = []
    private(set) var answers: [AnswerCard] = []
    private(set) var confirmQueue: [ConfirmRequest] = []
    private(set) var toast: Toast?
    /// 看不懂時的提示（顯示在輸入列上方）。
    private(set) var hint: String?
    private(set) var isOnline = true
    private(set) var isLoading = false
    private(set) var today: String

    /// 輸入列的文字。看不懂時會把原話放回來讓使用者補。
    var inputText = ""

    @ObservationIgnored let transactionRepository: TransactionRepository
    @ObservationIgnored let entryRepository: EntryRepository
    @ObservationIgnored private let days = Days.taipei
    @ObservationIgnored private var isFlushing = false
    @ObservationIgnored private var started = false

    static let examples = ["麥當勞 188", "早餐 65，午餐便當 120", "這個月花多少？"]
    static let toastSeconds: UInt64 = 5

    init(transactionRepository: TransactionRepository, entryRepository: EntryRepository) {
        self.transactionRepository = transactionRepository
        self.entryRepository = entryRepository
        self.today = Days.taipei.day(of: Date())
    }

    // MARK: - 衍生資料

    var sections: [DaySection] { Timeline.sections(from: transactions) }
    var monthExpense: Int { Timeline.monthExpense(from: transactions, monthOf: today) }
    var isEmpty: Bool { transactions.isEmpty && pending.isEmpty && answers.isEmpty }
    var isDemo: Bool { transactionRepository.isDemo }

    func category(_ id: UUID?) -> TxCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func title(for day: String) -> String {
        days.sectionTitle(for: day, today: today)
    }

    func transactions(withIds ids: [UUID]) -> [Txn] {
        let wanted = Set(ids)
        return transactions.filter { wanted.contains($0.id) }
            .sorted { ($0.occurredOn, $0.createdAt ?? "") > ($1.occurredOn, $1.createdAt ?? "") }
    }

    // MARK: - 啟動與同步

    /// App 開啟：先顯示本機快取，再跟伺服器同步，最後補送離線時留下的原話。
    func start() async {
        guard !started else { return }
        started = true
        transactions = transactionRepository.cachedTransactions()
        categories = transactionRepository.cachedCategories()
        pending = entryRepository.loadPending()
        answers = entryRepository.answers()
        await refresh()
        await flush()
    }

    /// 回到前景時：更新今天的日期、同步、補送。
    func becameActive() async {
        today = days.day(of: Date())
        guard started else { return }
        await refresh()
        await flush()
    }

    func refresh() async {
        guard isOnline else { return }
        isLoading = transactions.isEmpty
        defer { isLoading = false }
        if let fresh = try? await transactionRepository.refresh() {
            transactions = fresh.transactions
            categories = fresh.categories
        }
    }

    func connectivityChanged(online: Bool) {
        isOnline = online
        if online {
            Task {
                await refresh()
                await flush()
            }
        }
    }

    // MARK: - 記與問

    /// 送出一句話。輸入列立刻清空，可以接著記下一筆，不等伺服器回應。
    func submit(source: String = "text") {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= 500 else {
            hint = "內容太長了，請縮短到 500 字以內。"
            return
        }
        inputText = ""
        hint = nil
        let entry = PendingEntry(rawText: text, source: source, clientCreatedAt: Date())
        pending.append(entry)
        entryRepository.save(entry)
        Task { await flush() }
    }

    /// 依序送出待處理的原話。離線時什麼都不做，等恢復連線再來。
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while let next = PendingQueue.next(in: pending, online: isOnline) {
            var sending = next
            sending.state = .sending
            replace(sending)

            let (outcome, result) = await entryRepository.send(sending)
            if let updated = PendingQueue.apply(outcome, to: sending) {
                replace(updated)
                entryRepository.save(updated)
                // 連不上就先停，等網路恢復再繼續，避免空轉。
                if outcome == .networkFailure { break }
            } else {
                pending.removeAll { $0.id == sending.id }
                entryRepository.remove(sending.id)
                if let result { handle(result, for: sending) }
            }
        }
    }

    private func replace(_ entry: PendingEntry) {
        if let i = pending.firstIndex(where: { $0.id == entry.id }) { pending[i] = entry }
    }

    private func handle(_ result: RecordResult, for entry: PendingEntry) {
        switch result {
        case .committed(let items):
            merge(items)
            let total = items.reduce(0) { $0 + $1.amount }
            let message = items.count == 1 ? "已記錄 \(Money.format(total))" : "已記錄 \(items.count) 筆，共 \(Money.format(total))"
            show(Toast(message: message, undoCommitted: items))
        case .needsConfirm(let drafts):
            confirmQueue.append(ConfirmRequest(id: entry.id, rawText: entry.rawText, drafts: drafts))
        case .answer(let answer):
            answers.append(entryRepository.saveAnswer(question: entry.rawText, answer: answer))
            if answers.count > LocalStore.maxAnswers { answers.removeFirst(answers.count - LocalStore.maxAnswers) }
        case .unclear(let message):
            hint = message
            // 原話放回輸入列讓使用者補；如果已經在打下一句就不蓋掉。
            if inputText.isEmpty { inputText = entry.rawText }
        case .cancelled:
            break
        }
    }

    private func merge(_ items: [Txn]) {
        transactionRepository.absorb(items)
        let ids = Set(items.map(\.id))
        transactions.removeAll { ids.contains($0.id) }
        transactions += items
    }

    func retry(_ entry: PendingEntry) {
        let retried = PendingQueue.retried(entry)
        replace(retried)
        entryRepository.save(retried)
        Task { await flush() }
    }

    func discard(_ entry: PendingEntry) {
        pending.removeAll { $0.id == entry.id }
        entryRepository.remove(entry.id)
    }

    func useExample(_ text: String) {
        inputText = text
        hint = nil
    }

    func clearHint() {
        hint = nil
    }

    // MARK: - 確認卡

    /// 全部確認。成功回傳 nil，失敗回傳給使用者看的訊息。
    func confirm(_ request: ConfirmRequest, drafts: [Draft]) async -> String? {
        do {
            let items = try await entryRepository.confirm(entryId: request.id, drafts: drafts)
            merge(items)
            confirmQueue.removeAll { $0.id == request.id }
            let total = items.reduce(0) { $0 + $1.amount }
            show(Toast(message: "已記錄 \(Money.format(total))", undoCommitted: items))
            return nil
        } catch let error as BackendError {
            return error.message
        } catch {
            return "發生了一點問題，請稍後再試。"
        }
    }

    func cancelConfirm(_ request: ConfirmRequest) {
        confirmQueue.removeAll { $0.id == request.id }
        Task { try? await entryRepository.cancelConfirm(entryId: request.id) }
    }

    // MARK: - 編輯、刪除、復原

    func delete(_ item: Txn) async {
        guard isOnline else {
            show(Toast(message: "離線時不能刪除，連上網路後再試。"))
            return
        }
        do {
            try await transactionRepository.delete(item.id)
            transactions.removeAll { $0.id == item.id }
            show(Toast(message: "已刪除「\(item.item)」", undoDeleted: item))
        } catch {
            show(Toast(message: "刪除失敗，請稍後再試。"))
        }
    }

    /// 按下提示條上的「復原」。
    func undo(_ toast: Toast) async {
        self.toast = nil
        if let deleted = toast.undoDeleted {
            if (try? await transactionRepository.restore(deleted)) != nil {
                transactions.append(deleted)
            } else {
                show(Toast(message: "復原失敗，請稍後再試。"))
            }
        }
        for item in toast.undoCommitted {
            if (try? await transactionRepository.delete(item.id)) != nil {
                transactions.removeAll { $0.id == item.id }
            } else {
                show(Toast(message: "復原失敗，請稍後再試。"))
            }
        }
    }

    /// 編輯畫面存檔後，把結果放回時間軸。
    func applySaved(_ item: Txn) {
        transactions.removeAll { $0.id == item.id }
        transactions.append(item)
    }

    func dismissAnswer(_ card: AnswerCard) {
        answers.removeAll { $0.id == card.id }
        entryRepository.removeAnswer(card.id)
    }

    /// 手機上有沒有還沒備份的東西（決定用 Apple ID 登入時能不能直接換成舊帳號）。
    var hasLocalData: Bool { !transactions.isEmpty || !pending.isEmpty }

    /// 換成另一個帳號之後（用 Apple ID 取回舊資料），整個重新同步。
    func reloadAfterAccountSwitch() async {
        resetAfterWipe()
        await refresh()
    }

    /// 刪除所有資料之後，清空畫面上的狀態。
    func resetAfterWipe() {
        transactions = []
        pending = []
        answers = []
        confirmQueue = []
        toast = nil
        hint = nil
    }

    // MARK: - 提示條

    private func show(_ toast: Toast) {
        self.toast = toast
        Task { [id = toast.id] in
            try? await Task.sleep(nanoseconds: Self.toastSeconds * 1_000_000_000)
            if self.toast?.id == id { self.toast = nil }
        }
    }

    func dismissToast() {
        toast = nil
    }
}
