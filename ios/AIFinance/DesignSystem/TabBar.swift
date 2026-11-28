import SwiftUI

/// 四格：設定－記一筆－明細－分析，系統原生分頁列（自畫的懸浮膠囊會蓋住分析頁底部的字）。
/// 記一筆那格不是一頁：點了彈出記一筆視窗（蓋住分頁列），記下後切到明細（多米 2026-11-28）。
enum Page: Hashable {
    case settings
    case entry
    case ledger
    case analysis
}

extension EnvironmentValues {
    /// 這一頁是不是現在選中的分頁。藏起來的頁用它關掉只該出現一次的東西（提示條、廣告）。
    @Entry var isCurrentPage = true
}
