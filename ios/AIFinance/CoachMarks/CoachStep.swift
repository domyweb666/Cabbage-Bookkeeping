import SwiftUI

/// 聚光燈引導的一步。新增或調整步驟只改 CoachTour.steps，不動其他程式。
/// 白菜記帳只有一個主畫面，所以沒有「目標在哪個分頁」這個欄位。
struct CoachStep: Identifiable {
    let id: String
    /// 要照亮的元件代號，對應 .coachTarget("...")。
    let targetID: String
    let title: String
    let body: String
    /// 說明卡上小白菜做的動作。
    let action: MascotAction
    /// 洞比目標外擴多少。
    var holePadding: CGFloat = CoachStyle.holePadding
    /// 洞的圓角；nil 代表圓形按鈕，用洞高的一半。
    var holeCornerRadius: CGFloat? = CoachStyle.holeCornerRadius
}

enum CoachTour {
    /// 記完第一筆之後才出現，所以第一步指的是剛入帳的那一筆。
    static let steps: [CoachStep] = [
        CoachStep(
            id: "row",
            targetID: "timeline.row",
            title: "這筆記好了",
            body: "我是小白菜。點這一筆可以改內容，往左滑就是刪除。",
            action: .cheer
        ),
        CoachStep(
            id: "monthTotal",
            targetID: "header.monthTotal",
            title: "這個月花了多少",
            body: "點這個數字，看本月的分類和日常開銷。",
            action: .point(.up)
        ),
        CoachStep(
            id: "send",
            targetID: "input.send",
            title: "想自己填也行",
            body: "長按這顆可以手動新增。想查帳就直接問我。要再看一次，設定裡有「重看教學」。",
            action: .bow,
            holeCornerRadius: nil
        ),
    ]
}

/// 引導的視覺與動畫數值集中在這裡。顏色取用 Theme。
enum CoachStyle {
    static let dimOpacity = 0.55
    static let dimOpacityDark = 0.65

    static let holePadding: CGFloat = 8
    static let holeCornerRadius: CGFloat = 16
    static let glowWidth: CGFloat = 3
    static let glowRadius: CGFloat = 12
    static let glowOpacity = 0.8
    static let holeSpring = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let fadeSeconds = 0.25

    static let cardMargin: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardFadeSeconds = 0.18
    /// 卡片高度上限占螢幕的比例；內文超過就在卡片裡捲動。
    static let cardMaxHeightRatio: CGFloat = 0.4

    /// 每字 0.03 秒，標點後多停 0.12 秒。
    static let typeNanoseconds: UInt64 = 30_000_000
    static let punctuationNanoseconds: UInt64 = 150_000_000
    static let punctuation: Set<Character> = ["，", "。", "、", "！", "？", "：", "；"]

    static let dotSize: CGFloat = 5
    static let dotSpacing: CGFloat = 4
    static let dotActiveWidth: CGFloat = 14

    static let buttonHeight: CGFloat = 36
    static let minimumTap: CGFloat = 44
    static let skipTop: CGFloat = 8
    static let skipTrailing: CGFloat = 16

    /// 目標沒出現（例如清單是空的）等多久就跳下一步。
    static let missingTargetNanoseconds: UInt64 = 600_000_000
    /// 條件都符合後等多久才開始，讓鍵盤和彈出視窗先收完。
    static let startDelayNanoseconds: UInt64 = 600_000_000
}
