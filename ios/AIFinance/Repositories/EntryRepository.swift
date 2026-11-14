import FinanceCore
import Foundation

/// 原話的送出與待送佇列，以及確認、提問、回答卡。
@MainActor
final class EntryRepository {
    private let backend: Backend
    private let store: LocalStore
    private let days = Days.taipei

    init(backend: Backend, store: LocalStore) {
        self.backend = backend
        self.store = store
    }

    // MARK: - 待送佇列

    /// App 啟動時讀回佇列；上次停在「傳送中」的改回「等待」。
    func loadPending() -> [PendingEntry] {
        let recovered = PendingQueue.recovered(store.pending())
        recovered.forEach(store.savePending)
        return recovered
    }

    func save(_ entry: PendingEntry) {
        store.savePending(entry)
    }

    func remove(_ id: UUID) {
        store.removePending(id)
    }

    /// 送出一筆原話。同一個 entry_id 重送是安全的，後端只會處理一次。
    func send(_ entry: PendingEntry) async -> (outcome: SendOutcome, result: RecordResult?) {
        do {
            let result = try await backend.record(
                entryId: entry.id, rawText: entry.rawText, source: entry.source,
                clientCreatedAt: days.iso8601(entry.clientCreatedAt)
            )
            return (.delivered, result)
        } catch let error as BackendError {
            return (error.isNetwork ? .networkFailure : .rejected(error.message), nil)
        } catch {
            return (.networkFailure, nil)
        }
    }

    // MARK: - 確認與提問

    func confirm(entryId: UUID, drafts: [Draft]) async throws -> [Txn] {
        if case .committed(let items) = try await backend.confirm(entryId: entryId, drafts: drafts) { return items }
        return []
    }

    func cancelConfirm(entryId: UUID) async throws {
        try await backend.cancelConfirm(entryId: entryId)
    }

    // MARK: - 回答卡

    func answers() -> [AnswerCard] { store.answers() }

    func saveAnswer(question: String, answer: AskAnswer) -> AnswerCard {
        let card = AnswerCard(id: UUID(), question: question, answer: answer, createdAt: Date())
        store.addAnswer(card)
        return card
    }

    func removeAnswer(_ id: UUID) {
        store.removeAnswer(id)
    }
}
