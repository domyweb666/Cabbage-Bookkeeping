import FinanceCore
import Foundation

// 掃過的發票：按「記下」存成功後才記，同一張再掃到時提醒一句。
// 存在 App 自己的 Application Support/invoices.json，只放號碼和日期，不放金額和品名。
// 讀寫失敗都往外丟；這份只拿來提醒，讀不到時畫面照樣讓人記。

@MainActor
final class InvoiceLog {
    struct Entry: Codable, Hashable {
        let number: String
        /// 開立日期 yyyy-MM-dd。號碼每兩個月換一輪，配上日期才不會認錯。
        let day: String
        let savedAt: Date
    }

    private struct File: Codable {
        var version = 1
        var invoices: [Entry]
    }

    static let shared = InvoiceLog()

    /// nil 就是只放記憶體（-memoryStore），關掉 App 就忘記。
    private let file: URL?
    private var memory: [Entry] = []

    private init() {
        if AppConfig.current.inMemory {
            file = nil
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            file = support.appendingPathComponent("invoices.json")
        }
    }

    private func load() throws -> [Entry] {
        guard let file else { return memory }
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        return try JSONDecoder().decode(File.self, from: data).invoices
    }

    /// 這張記過了沒。
    func contains(_ invoice: InvoiceQR) throws -> Bool {
        try load().contains { $0.number == invoice.number && $0.day == invoice.day }
    }

    /// 記下這張。先讀舊的再寫，舊檔壞了就丟出去，不會蓋掉。
    func record(_ invoice: InvoiceQR) throws {
        var rows = try load()
        guard !rows.contains(where: { $0.number == invoice.number && $0.day == invoice.day }) else { return }
        rows.append(Entry(number: invoice.number, day: invoice.day, savedAt: Date()))
        guard let file else {
            memory = rows
            return
        }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(File(invoices: rows)).write(to: file, options: .atomic)
    }

    /// 清除所有資料時用。
    func eraseAll() throws {
        memory = []
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
