import SwiftUI

// 分析頁幾種看法共用的字樣：卡片標題、第一行的答案、下面的小字。跟 AnalysisView 裡的一樣。

struct AnalysisCardTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typo.subheadline.font)
            .foregroundStyle(Theme.secondaryText)
    }
}

struct AnalysisAnswer: View {
    let text: String
    let id: String

    init(_ text: String, id: String) {
        self.text = text
        self.id = id
    }

    var body: some View {
        Text(text)
            .font(Typo.body.font.weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }
}

struct AnalysisSmall: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typo.footnote.font)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 整列可以按、右邊一個箭頭的一句話。
struct AnalysisLinkRow: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Gap.item) {
                Text(text)
                    .font(Typo.body.font.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Typo.footnote.font)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Metric.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
    }
}
