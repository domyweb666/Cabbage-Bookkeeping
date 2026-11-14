import SwiftUI
import UIKit

// 顏色、字級、間距集中在這裡（規格 7.1）。畫面裡不直接寫色碼。

extension Color {
    /// 依淺色／深色模式切換的顏色。
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum Theme {
    static let background = Color(light: 0xF5F5F7, dark: 0x000000)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let primaryText = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let secondaryText = Color(light: 0x86868B, dark: 0x98989D)
    static let accent = Color(light: 0x8B5A71, dark: 0xC792AB)
    static let income = Color(light: 0x329B79, dark: 0x4CC29B)
    static let expense = Color(light: 0xE56B72, dark: 0xF0868C)
    static let separator = Color(light: 0xE5E5EA, dark: 0x2C2C2E)

    static let cardRadius: CGFloat = 20
    /// 基本間距 8pt，其他間距都是它的倍數。
    static let unit: CGFloat = 8

    static func spacing(_ multiple: CGFloat) -> CGFloat { unit * multiple }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.spacing(2)

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Theme.spacing(2)) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

/// 金額文字：數字等寬，避免跳動。
struct AmountText: View {
    let text: String
    var color: Color = Theme.primaryText
    var font: Font = .body

    var body: some View {
        Text(text)
            .font(font.monospacedDigit())
            .foregroundStyle(color)
    }
}

/// 小標籤（標籤、原因）。
struct Chip: View {
    let text: String
    var tint: Color = Theme.secondaryText

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.unit)
            .padding(.vertical, Theme.unit / 2)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
