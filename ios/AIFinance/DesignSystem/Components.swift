import SwiftUI

// 全部畫面共用的小元件，只用 Theme.swift 的代號組。

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Gap.cardPad)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }

    /// 分組圓角的清單：左右跟標題對齊，底色由外面的頁面鋪。
    func ledgerList() -> some View {
        listStyle(.insetGrouped)
            .contentMargins(.horizontal, Gap.screenMargin, for: .scrollContent)
            .scrollContentBackground(.hidden)
    }

    /// 沒有導覽列的分頁往上捲時，字不要疊到時間和電量。
    func coversStatusBar() -> some View {
        overlay(alignment: .top) {
            GeometryReader { geo in
                Theme.background
                    .frame(height: geo.safeAreaInsets.top)
                    .offset(y: -geo.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 主要動作的底色和字色，能不能按一眼看得出來。放在按鈕的 label 上，尺寸先定好再套。
    func primaryFill() -> some View {
        modifier(PrimaryFill())
    }
}

/// 金額文字：數字等寬，避免跳動。給了 value，數字變的時候會滾過去。
struct AmountText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    var value: Int?
    var color: Color = Theme.primaryText
    var font: Font = Typo.body.font

    var body: some View {
        Text(text)
            .font(font.monospacedDigit())
            .foregroundStyle(color)
            .contentTransition(transition)
            .animation(Motion.change, value: value)
    }

    private var transition: ContentTransition {
        guard let value else { return .identity }
        return reduceMotion ? .opacity : .numericText(value: Double(value))
    }
}

/// 自己畫外觀的按鈕都用這個。清單裡整列的按鈕用 .row，變淡就好，不縮小。
struct PressStyle: ButtonStyle {
    var scales = true

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, scales: scales)
    }
}

/// 另外包一層 View 才讀得到環境值。
private struct PressBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let scales: Bool

    var body: some View {
        configuration.label
            .scaleEffect(scales && !reduceMotion && configuration.isPressed ? Motion.pressScale : 1)
            .opacity(configuration.isPressed ? Motion.pressOpacity : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
    static var row: PressStyle { PressStyle(scales: false) }
}

private struct PrimaryFill: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .font(Typo.headline.font)
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.secondaryText)
            .background(isEnabled ? Theme.accent : Theme.disabled)
    }
}

/// 設定頁的一組：標題加一張卡，卡裡放列。
struct RowCard<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.item) {
            Text(title)
                .font(Typo.title3.font)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, Gap.cardPad)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Metric.hairline)
            .accessibilityHidden(true)
    }
}

/// 空的、讀不出來：用系統的空狀態元件，放字就好。
struct EmptyMessage: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Text(title)
                .font(Typo.title3.font)
                .foregroundStyle(Theme.primaryText)
        } description: {
            Text(message)
                .font(Typo.subheadline.font)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
