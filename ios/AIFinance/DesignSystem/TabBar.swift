import SwiftUI

/// 三個分頁：設定－明細－分析，用系統原生分頁列（多米 2026-11-27：自畫的懸浮膠囊改回原生，
/// 懸浮那條會蓋住分析頁底部的字）。記一筆是彈出視窗，開 app 自動彈出，明細頁底部也有一顆。
enum Page: Hashable {
    case settings
    case ledger
    case analysis
}

extension EnvironmentValues {
    /// 這一頁是不是現在選中的分頁。藏起來的頁用它關掉只該出現一次的東西（提示條、廣告）。
    @Entry var isCurrentPage = true
}
