import FinanceCore

// 畫面上的字集中在三個地方：這個檔、FinanceCore/AnalysisText.swift（有數字的句子）、VeggieText（全家共用的列名）。
// 分類的名字在 FinanceCore/Categories.swift。改字先對詞彙表。
//
// 詞彙表
// | 東西或動作 | 定下來的名字 | 不叫 |
// |---|---|---|
// | 新增一筆 | 記一筆、記下 | 新增、儲存 |
// | 一筆資料 | 紀錄 | 交易、項目、流水 |
// | 記帳畫面上的格子 | 分類 | 類別、標籤 |
// | 勾起來會顯示的那些分類 | 常用分類、顯示中 | 我的分類、最愛 |
// | 錢出去、錢進來 | 支出、收入 | 花費、入帳 |
// | 跟平常比不算的那一筆 | 一次性 | 非常態、特殊 |
// | 每個月打算花多少 | 每月預算 | 目標、額度 |
// | 到那天自己記一筆的 | 固定支出 | 定期、週期、自動扣款 |
// | 把剛才的動作收回來 | 復原 | 還原、恢復 |

enum Words {
    static let cancel = "取消"
    static let done = "完成"
    static let ok = "好"
    static let currency = "NT$"

    enum Tab {
        static let entry = "記一筆"
        static let ledger = "明細"
        static let analysis = "分析"
        static let settings = "設定"
    }

    enum Failure {
        static let storeTitle = "打不開紀錄"
        static let storeMessage = "紀錄還在，沒有被刪掉。先把 App 整個關掉再開一次。手機空間不夠時也會這樣，清出空間後再試。"
        static let loadTitle = "紀錄讀不出來"
        static let loadMessage = "紀錄還在，沒有被刪掉。先把 App 整個關掉再開一次。"
        static let loadToast = "紀錄還在，這次讀不出來。把 App 關掉再開一次。"
        static let saveToast = "這次沒有存成，原本的紀錄沒有變。"
        static let saveTitle = "沒有存成功"
        static let saveMessage = "填好的內容還在這一頁。手機空間可能不夠，清出空間後再按一次。"
        static let export = "紀錄還在，這次沒有匯出成功。手機空間可能不夠。"
        static let eraseAll = "這次沒有刪成，資料還在。"
    }

    enum Ledger {
        static let monthTotal = "本月支出"
        static let add = "記一筆"

        static func dayTotal(_ amount: Int) -> String { "共 \(Money.grouped(amount))" }
        static func monthSpoken(total: Int, budget: String?) -> String {
            [monthTotal + " " + Money.format(total), budget].compactMap { $0 }.joined(separator: "，")
        }

        static let undo = "復原"
        static let emptyTitle = "還沒有紀錄"
        static let emptyMessage = "按下面的「記一筆」，選金額和分類就好。"
        static let delete = "刪除"
        static let otherCategory = "其他"
        static let oneOff = "一次性"

        static func deleted(_ title: String) -> String { "已刪除「\(title)」" }

        static func savedEarlier(_ category: TxCategory, _ amount: Int) -> String {
            "記好了。\(category.name) \(Money.format(amount))"
        }
    }

    enum Entry {
        static let kind = "類型"
        static let save = "記下"
        static let backspace = "退格"
        static let date = "日期"
        static let note = "備註"

        /// 備註欄裡的問句：看分類問一句，讓人順手回答。不寫「可以不填」（多米 2026-11-26 QC-0015 #126）。
        static func notePrompt(_ category: TxCategory?) -> String {
            guard let category else { return "這筆是什麼？" }
            switch category.tint {
            case .food: return "吃了什麼？"
            case .transport: return "去哪裡？"
            case .home: return "家裡用在哪？"
            case .shopping: return "買了什麼？"
            case .other: return "這筆花在哪？"
            case .income: return "哪裡來的？"
            }
        }
        static let oneOffOn = "一次性，不跟平常比"
        static let delete = "刪除"
        static let deleteTitle = "刪除這筆紀錄？"
        static let deleteConfirm = "刪除這筆"
        static let category = "分類"
        static let pickCategory = "選分類"
        static let editCategories = "編輯"

        static func picked(_ name: String) -> String { "分類，\(name)" }
        static let editCategoriesSpoken = "編輯常用分類"
    }

    enum Categories {
        static let title = "常用分類"
        static let shown = "顯示中"
        static let hint = "有顏色的會出現在記一筆，點一下放進去或拿出來。按住一格可以改名字和圖示。拿出來不會動到已經記的。"
        static let keepOne = "至少留一個。"
        static let add = "新增分類"
        static let reset = "恢復預設"

        static func edit(_ name: String) -> String { "編輯\(name)" }
        static func resetTitle(_ kind: TxType) -> String { "\(kind.label)分類恢復預設？" }
        static func resetMessage(_ kind: TxType) -> String {
            "\(kind.label)顯示哪些、順序、內建的名字與圖示都會恢復。自己新增的分類還在，變成沒勾。"
        }
    }

    enum CategoryEdit {
        static let newTitle = "新增分類"
        static let editTitle = "編輯分類"
        static let save = "存分類"
        static let nameSection = "名字"
        static let namePrompt = "1 到 8 個字"
        static let iconSection = "圖示"
        static let restore = "恢復原本的名字與圖示"
        static let delete = "刪除這個分類"
        static let deleteMessage = "記過的紀錄還在，也照樣看得到這個名字，以後不能再選。"
        static let lastOne = "顯示中剩這一個，先勾別的才能刪。"

        static func icon(_ number: Int) -> String { "圖示 \(number)" }
        static func deleteTitle(_ name: String) -> String { "刪除「\(name)」？" }

        /// 名字裡有這兩個字，就提醒刷卡和繳卡費不要各記一次。
        static let cardBill = "卡費"
        static let cardBillHint = "刷卡那天記過的，繳卡費不用再記。"

        static func problem(_ problem: CategoryNameProblem) -> String {
            switch problem {
            case .empty: return "要有名字。"
            case .tooLong: return "最多 \(CategoryBook.maxNameLength) 個字。"
            case .duplicate: return "已經有同名的分類，換一個名字。"
            }
        }
    }

    enum Analysis {
        static let title = "分析"
        static let previousMonth = "上個月"
        static let nextMonth = "下個月"
        static let setBudget = "訂每月預算"
        static let noBudget = "這個月沒有訂預算。"

        static func income(_ amount: Int) -> String { "收入 \(Money.format(amount))" }
        static let estimateAmount = "大概的金額"
        static let estimateNote = "會記在「其他」，之後可以改。"
        static let estimateSave = "補上"

        static func savedEstimate(_ amount: Int) -> String { "記好了。大概 \(Money.format(amount))" }
        static func showAll(_ count: Int) -> String { "看全部 \(count) 類" }

        static func detailHeader(month: String, count: Int, total: Int) -> String {
            "\(Days.shortMonth(of: month)) \(count) 筆，共 \(Money.format(total))"
        }
    }

    enum Budget {
        static let title = "每月預算"
        static let save = "存預算"
        static let clear = "不訂預算"
        static let fixedHint = "房租、保費這種固定的設一次，還能花會先扣掉。"
    }

    enum Fixed {
        static let title = "固定支出"
        static let add = "新增固定支出"
        static let editTitle = "改固定支出"
        static let monthly = "每月"
        static let yearly = "每年"
        static let emptyTitle = "還沒有固定支出"
        static let emptyMessage = "房租、電信、保費設一次，到那天自己記一筆，還能花也會先扣掉。"
        static let kind = "多久一次"
        static let amount = "金額"
        static let name = "名稱，可以不填"
        static let day = "哪一天"
        static let monthLabel = "月"
        static let dayLabel = "日"
        static let category = "分類"
        static let lateDay = "沒有這一天的月份，記在最後一天。"
        static let save = "存"
        static let delete = "刪除這項"
        static let deleteNote = "記過的還在，以後不再自動記。"

        static func count(_ count: Int) -> String { count == 0 ? "還沒設" : "\(count) 項" }
        static func month(_ number: Int) -> String { "\(number) 月" }
        static func monthDay(_ number: Int) -> String { "\(number) 號" }
        static func yearDay(_ number: Int) -> String { "\(number) 日" }
    }

    enum Settings {
        static let title = "設定"
        static let appSection = "記帳"
        static let privacy = "隱私說明"
        static let eraseTitle = "清除所有資料？"
        static let eraseMessage = "所有紀錄、預算、固定支出和收據照片都會從這支手機刪除，設定也會回到第一次打開的樣子。刪了就救不回來。"
        static let exportFirst = "先匯出"
        static let eraseContinue = "繼續"
        static let eraseAgainTitle = "真的要全部刪除？"
        static let eraseConfirm = "全部刪除"
        static let erased = "所有資料都刪除了。"
        static let privacyLines = [
            "紀錄、預算、固定支出、帳本、存錢目標和分類設定都存在這支手機上，不會上傳，App 也不連網路。",
            "分析頁的數字全部在手機上算。",
            "收據照片和掃過的發票號碼也只存在這支手機上。按「掃發票」或拍收據時才會問相機權限；"
                + "選照片走系統的畫面，App 看不到相簿裡其他照片。",
            "手機有開 iCloud 備份的話，紀錄、預算、固定支出和分類設定會跟著整支手機一起備份。",
            "刪掉的單筆紀錄會留在手機上、不再顯示也不再計算，按「清除所有資料」才會整份清掉。",
            "設定裡可以匯出全部紀錄，也可以全部刪除。把 App 刪掉，紀錄也會跟著刪掉。",
            "小工具用的數字，App 會在這支手機上另外放一份：這個月支出的金額、日期和分類，預算，固定支出，存錢目標的金額和日期。"
                + "裡面沒有備註，按「清除所有資料」會一起清空。",
            "小工具放在鎖定畫面，別人拿起手機可能看得到數字。",
            "在「蔬菜家族的其他 app」點一個 App，手機會打開 App Store 或網頁。"
                + "點設定頁最下面的圖示，手機會打開 DOMYWEB 的網站、Facebook 或 Instagram。",
            "在設定頁最下面長按版本號，白菜記帳會把 App 版本、iOS 版本、機型代號和手機語言放進剪貼簿，"
                + "裡面沒有紀錄。白菜記帳不會把這段字傳出去。",
        ]

        static func exportName(_ day: String) -> String { "白菜記帳_\(day).csv" }
    }
}
