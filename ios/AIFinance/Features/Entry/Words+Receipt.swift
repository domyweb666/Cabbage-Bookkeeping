import FinanceCore
import Foundation

// 收據照片和掃發票的字。共用的 Words.swift 不動，這兩塊的字放這裡。

extension Words {
    enum Receipt {
        static let add = "加收據照片"
        static let addMore = "再加一張收據照片"
        static let camera = "拍照"
        static let library = "從相簿選"
        static func photo(_ number: Int) -> String { "收據照片 \(number)" }
        static let viewTitle = "收據照片"
        static let delete = "刪除"
        static let deleteTitle = "刪除這張照片？"
        static let deleteConfirm = "刪除照片"
        static let failedTitle = "照片沒有存成"
        static let failedMessage = "紀錄沒有變。手機空間可能不夠，清出空間後再試一次。"
        static let loadFailedTitle = "照片讀不出來"
        static let loadFailedMessage = "紀錄沒有變。先把 App 整個關掉再開一次。"
        static let deleteFailedMessage = "這次沒有刪成，照片還在。"
    }

    enum Camera {
        static let offTitle = "相機沒有打開"
        static let offMessage = "到設定打開白菜記帳的相機，就能拍收據和掃發票。"
        static let openSettings = "打開設定"
        static let missing = "這台裝置沒有相機，沒辦法掃發票。"
    }

    enum Invoice {
        static let scan = "掃發票"
        static let hint = "對準發票左邊的 QR 碼"
        static let seenTitle = "這張發票記過了"
        /// 哪一天、多少錢，認得出是哪一張。
        static func seenMessage(_ invoice: InvoiceQR) -> String {
            "\(invoice.day)，\(Words.currency)\(Money.grouped(invoice.total))"
        }
        static let recordAnyway = "還是要記"
    }
}

