import SwiftUI
import UIKit

// 顏色、字級、間距集中在這裡。畫面裡不直接寫色碼。

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
    /// 放在主色上面的字。
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let income = Color(light: 0x329B79, dark: 0x4CC29B)
    /// 圖上「平常範圍」那一條的底色。
    static let band = Color(light: 0xD9D9DE, dark: 0x48484A)

    static let cardRadius: CGFloat = 20
    static let keyRadius: CGFloat = 14

    /// 間距照用途取名（多米 iOS 準則 3-46）。
    enum Gap {
        /// 安全區上緣到大標題。給 ScrollView 拼的分頁頁用。
        static let pageTop: CGFloat = 40
        /// 畫面左右邊距。
        static let screen: CGFloat = 20
        /// 不同性質的兩塊。
        static let section: CGFloat = 24
        /// 同一組的兄弟。
        static let group: CGFloat = 12
        /// 標籤跟它自己的內容。
        static let item: CGFloat = 8
        /// 黏在一起的一對。
        static let tight: CGFloat = 4
        /// 卡片內距。
        static let card: CGFloat = 16
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.Gap.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Theme.Gap.card) -> some View {
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

/// 整條寬的主要按鈕。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35))
            .clipShape(Capsule())
    }
}
