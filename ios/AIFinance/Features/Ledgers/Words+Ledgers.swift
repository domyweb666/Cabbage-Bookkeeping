import FinanceCore
import SwiftUI

// 多帳本與存錢的字。有數字的存錢句子在 FinanceCore/Savings.swift（SavingsText），小工具也用得到。
//
// 詞彙表（補）
// | 東西或動作 | 定下來的名字 | 不叫 |
// |---|---|---|
// | 分開記的一本 | 帳本 | 帳戶、錢包、群組 |
// | 想在哪天前存到一筆錢 | 存錢 | 目標、儲蓄計畫、達成 |

extension Words {
    enum Ledgers {
        static let title = "帳本"
        static let add = "新增帳本"
        static let editTitle = "改帳本"
        static let name = "名字"
        static let namePrompt = "例如：日本旅行"
        static let color = "顏色"
        static let note = "紀錄、預算、固定支出每本分開；常用分類大家共用。"
        static let create = "建立帳本"
        static let save = "存"
        static let rename = "改名字"
        static let delete = "刪除"
        static let deleteConfirm = "刪除這本"
        static let listHint = "點一下換到那本。按住可以改名字、刪除。"
        static let lastOne = "至少要留一本，最後一本不能刪。"
        static let duplicate = "已經有一本叫這個名字。"

        static func monthSpent(_ amount: Int) -> String { "這個月 \(Money.format(amount))" }
        static func chipSpoken(_ name: String) -> String { "帳本，\(name)" }
        static func deleteTitle(_ name: String) -> String { "刪除「\(name)」？" }
        static func deleteMessage(records: Int) -> String {
            let what = records > 0 ? "這本的 \(records) 筆紀錄、固定支出和存錢" : "這本的固定支出和存錢"
            return "\(what)會一起刪掉，其他帳本不受影響。刪了就救不回來。"
        }

        /// 讀螢幕念的顏色名字。
        static func colorName(_ color: LedgerColor) -> String {
            switch color {
            case .plum: "梅紫"
            case .terracotta: "磚紅"
            case .blue: "藍"
            case .olive: "橄欖綠"
            case .violet: "紫"
            case .green: "綠"
            }
        }
    }

    enum Saving {
        static let title = SavingsText.title
        static let start = "開始存錢"
        static let again = "再存一次"
        static let edit = "改存錢"
        static let stop = "不存了"
        static let stopTitle = "不存了？"
        static let stopMessage = "記過的紀錄不會動，之後可以再開始。"
        static let amount = "想存多少"
        static let deadline = "在哪天前"
        static let name = "存來做什麼，可以不填"
        static let save = "存"
        static let notYet = "還沒開始"
        static let emptyTitle = "還沒開始存錢"
        static let emptyMessage = "訂一個金額和日子，之後記的收入減掉支出，就是存下來的。"
        static let startHint = "想在哪天前存到一筆錢，記帳時就幫你算。"

        /// 設定頁那一列右邊。
        static func settingsValue(_ progress: SavingsProgress?, today: String) -> String {
            progress.map { SavingsText.short($0, today: today) } ?? notYet
        }
    }
}

extension LedgerColor {
    /// 帳本的顏色。全部從 Theme 拿，深色模式跟著變。
    var color: Color {
        switch self {
        case .plum: Theme.accent
        case .terracotta: Theme.tint(.food)
        case .blue: Theme.tint(.transport)
        case .olive: Theme.tint(.home)
        case .violet: Theme.tint(.shopping)
        case .green: Theme.income
        }
    }
}
