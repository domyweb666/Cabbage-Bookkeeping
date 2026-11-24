import SwiftUI
import VeggieKit

// 蔬菜家族共用元件在這個 app 的設定。值是 nil 的那一列，設定頁整列不出現。

extension VeggieConfig {
    static let baicai = VeggieConfig(
        name: "白菜記帳",
        slug: "baicai",
        // 分享列要有 Apple ID 才出現，這句現在還看不到。等多米定。
        tagline: "按金額、點分類就記好一筆",
        appStoreID: nil,
        supportEmail: nil,
        privacyURL: nil
    )
}

extension VeggieStyle {
    static let baicai = VeggieStyle(
        textPrimary: Theme.primaryText,
        textSecondary: Theme.secondaryText,
        textTertiary: Theme.tertiaryText,
        accent: Theme.accent,
        destructive: Theme.destructive,
        canvas: Theme.background,
        surface: Theme.card,
        body: Typo.body.font,
        headline: Typo.headline.font,
        subheadline: Typo.subheadline.font,
        footnote: Typo.footnote.font,
        rowHeight: Metric.row
    )
}
