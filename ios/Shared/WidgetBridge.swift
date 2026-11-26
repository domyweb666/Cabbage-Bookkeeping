import FinanceCore
import Foundation
import WidgetKit

/// App 和小工具共用的固定字串。改了會讓使用者放好的小工具失效，清單在 docs/不能改的字串.md。
enum Shared {
    static let appGroup = "group.org.domyweb.baicai"
    static let scheme = "baicai"
    static let entryHost = "entry"
    static let entryURL = URL(string: "\(scheme)://\(entryHost)")
    static let widgetKind = "org.domyweb.baicai.widget.left"
    /// 存錢的小工具（2026-11-26 新增）。
    static let savingsWidgetKind = "org.domyweb.baicai.widget.savings"
    static let controlKind = "org.domyweb.baicai.control.add"
}

/// 給小工具的一份快照，放在 App Group 的資料夾。App 寫，小工具讀。
/// 這裡失敗都不影響記帳：紀錄存在 App 自己的資料庫，小工具少更新一次而已。
enum WidgetBridge {
    private static let fileName = "widget.json"

    /// 群組沒開好時是 nil，那就沒有小工具可以更新。
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroup)?
            .appendingPathComponent(fileName)
    }

    /// 寫好並請小工具重畫。內容沒變就什麼都不做，給 nil 就把檔刪掉。回傳有沒有動到檔案。
    @discardableResult
    static func publish(_ snapshot: WidgetSnapshot?) -> Bool {
        guard let url = fileURL else { return false }
        do {
            if let snapshot {
                if snapshot == read() { return false }
                // 手機開機後解鎖過一次就讀得到，鎖著的時候小工具才畫得出來。
                try JSONEncoder().encode(snapshot)
                    .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else {
                guard FileManager.default.fileExists(atPath: url.path) else { return false }
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            return false
        }
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    /// 沒有、讀不懂、版本比這支新，都回 nil。
    static func read() -> WidgetSnapshot? {
        guard let url = fileURL else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: url))
            return snapshot.schemaVersion <= WidgetSnapshot.currentSchema ? snapshot : nil
        } catch {
            return nil
        }
    }
}
