import FinanceCore
import SwiftUI

// 這個 app 的短名。數值全在 DomyTokens.swift（從 domy-design 1.6.0 整份複製，不手改，要改回 domy-design 改）。
// 畫面檔只用這裡的名字，不寫色碼、字級、間距、圓角、秒數，也不寫 s1、s2 這種刻度名。

typealias Gap = DomyTokens.Layout
typealias Metric = DomyTokens.Size
typealias Typo = DomyTokens.TypeScale

enum Theme {
    // 產品色：梅紫。
    static let background = DomyTheme.plum.canvas
    static let accent = DomyTheme.plum.accent
    /// 放在主色上面的字。
    static let onAccent = DomyTheme.plum.onAccent
    /// 卡片上要跳出來的數字。
    static let accentStrong = DomyTheme.plum.strong

    // 中性色。
    static let card = DomyTokens.Neutral.surface
    static let primaryText = DomyTokens.Neutral.textPrimary
    static let secondaryText = DomyTokens.Neutral.textSecondary
    static let tertiaryText = DomyTokens.Neutral.textTertiary
    static let disabledText = DomyTokens.Neutral.textDisabled
    static let separator = DomyTokens.Neutral.separator
    static let destructive = DomyTokens.Neutral.destructive

    // 設計系統沒有、這個 app 自己要的顏色。對比用 design/contrast.py 算過。

    /// 收入的數字。
    static let income = Color(domyLight: 0x24785C, domyDark: 0x4CC29B)
    /// 還不能按的主要按鈕底色，字用 secondaryText。
    /// 設計系統的 surfaceMuted 偏米色，在灰白底上看不出是按鈕（多米 2026-11-25 回報過）。
    static let disabled = Color(domyLight: 0xE5E5EA, domyDark: 0x2C2C2E)
    /// 圖上「平常範圍」那一段。
    static let band = Color(domyLight: 0x8E8E93, domyDark: 0x7C7C82)

    /// 分類色塊，照大組配色，前四色跟蒜日子同一組。是哪一類的記號，不代表花多花少。
    static func tint(_ tint: CategoryTint) -> Color {
        switch tint {
        case .food: Color(domyLight: 0xA65F45, domyDark: 0xDB9C84)
        case .transport: Color(domyLight: 0x4B6C8F, domyDark: 0x8FB0D4)
        case .home: Color(domyLight: 0x7A6A3A, domyDark: 0xC2B078)
        case .shopping: Color(domyLight: 0x6F5F8F, domyDark: 0xA99BD0)
        case .other: Color(domyLight: 0x66666D, domyDark: 0xA1A1A8)
        case .income: income
        }
    }

    /// 放在分類色塊上的圖示。
    static let onTint = Color(domyLight: 0xFFFFFF, domyDark: 0x1D1D1F)

    static let cardRadius = DomyTokens.Radius.xl
    /// 分類色塊。
    static let badgeRadius = DomyTokens.Radius.md
    static let keyRadius = DomyTokens.Radius.lg
    /// 捲到底的留白。系統分頁列自己會讓位，不用 bottomClear。
    static let pageBottom = DomyTokens.Space.s8

    /// 這個 app 才有的尺寸。
    enum Part {
        /// 分類格。三排剛好連日期、備註都看得到。
        static let cell: CGFloat = 56
        static let cellIconWidth: CGFloat = 48
        static let cellIconHeight: CGFloat = 32
        /// 分類色塊。
        static let badge: CGFloat = 40
        /// 還沒選分類時的虛線框。
        static let emptyBadge = StrokeStyle(lineWidth: 2, dash: [5, 4])
        /// 鍵盤右邊退格、記下那一欄。
        static let keySide: CGFloat = 96
        /// 導覽列中間的支出／收入切換。
        static let kindPicker: CGFloat = 160
    }
}

/// 動作代號（準則 3-41、附錄 E）。畫面只從這裡拿動畫；秒數只寫在這裡，每一個都要寫，不寫的話預設是 0.5 秒。
/// 減少動態打開時：縮放不做、數字改淡入淡出、清單增減用 changeReduced、自動捲動直接到位。
enum Motion {
    static let press = Animation.snappy(duration: 0.15)
    static let change = Animation.snappy(duration: 0.25)
    static let changeReduced = Animation.easeInOut(duration: 0.2)
    static let pressScale: CGFloat = 0.96
    static let pressOpacity: Double = 0.85
}
