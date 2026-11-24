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
    /// 圖示的淡底，上面放 accent。
    static let accentSoft = DomyTheme.plum.soft

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

    static let cardRadius = DomyTokens.Radius.xl
    static let keyRadius = DomyTokens.Radius.lg
    /// 捲到底的留白。系統分頁列自己會讓位，不用 bottomClear。
    static let pageBottom = DomyTokens.Space.s8

    /// 這個 app 才有的尺寸。
    enum Part {
        /// 分類格。四排剛好連日期、備註都看得到。
        static let cell: CGFloat = 56
        static let cellIcon: CGFloat = 28
        /// 清單前面的分類圖示圓圈。
        static let badge = DomyTokens.Size.buttonCompact
        /// 鍵盤右邊退格、記下那一欄。
        static let keySide: CGFloat = 96
        /// 導覽列中間的支出／收入切換。
        static let kindPicker: CGFloat = 160
    }
}

/// 動作代號（準則附錄 E）。畫面只從這裡拿動畫，不寫秒數。
/// 減少動態打開時：縮放不做、數字改淡入淡出、清單增減不動。
enum Motion {
    static let press = Animation.snappy
    static let change = Animation.snappy
    static let pressScale: CGFloat = 0.96
    static let pressOpacity: Double = 0.85
}
