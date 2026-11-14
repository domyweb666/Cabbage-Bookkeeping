import SwiftUI

/// 說明卡：小白菜、進度小點、標題、逐字出現的內文、「知道了」按鈕。
struct CoachCard: View {
    let step: CoachStep
    let index: Int
    let total: Int
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownCount = 0
    @State private var revealed = false
    @AccessibilityFocusState private var focused: Bool

    private var isLast: Bool { index == total - 1 }
    private var isTyping: Bool { !revealed && shownCount < step.body.count }
    private var typedText: String { revealed ? step.body : String(step.body.prefix(shownCount)) }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.unit) {
            HStack(alignment: .top, spacing: Theme.spacing(1.5)) {
                MascotView(action: step.action, crop: .bust)
                    .frame(width: 60, height: 63)

                VStack(alignment: .leading, spacing: 6) {
                    dots
                    Text(step.title)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    // 字級放到很大、內文放不下時，改成在卡片裡捲動。
                    ViewThatFits(in: .vertical) {
                        bodyText
                        ScrollView { bodyText }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // VoiceOver 一次讀出步數、標題與全文，不跟著打字機逐字念。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("第 \(index + 1) 步，共 \(total) 步。\(step.title)。\(step.body)")
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("coachCardText")
                .accessibilityFocused($focused)
            }

            Button {
                // 內文還在打字就先一次顯示全文，已經顯示完才前進。
                if isTyping { revealed = true } else { onNext() }
            } label: {
                Text(isLast ? "開始吧" : "知道了")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.spacing(2))
                    .frame(height: CoachStyle.buttonHeight)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                    .frame(minWidth: CoachStyle.minimumTap, minHeight: CoachStyle.minimumTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coachNext")
        }
        .padding(CoachStyle.cardPadding)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: CoachStyle.cardRadius, style: .continuous))
        .task { await runTypewriter() }
    }

    /// 先用看不見的全文把高度占好，打字時卡片才不會一直長高。
    private var bodyText: some View {
        Text(step.body)
            .hidden()
            .overlay(alignment: .topLeading) { Text(typedText) }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dots: some View {
        HStack(spacing: CoachStyle.dotSpacing) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Theme.secondaryText.opacity(0.3))
                    .frame(width: i == index ? CoachStyle.dotActiveWidth : CoachStyle.dotSize, height: CoachStyle.dotSize)
            }
        }
    }

    private func runTypewriter() async {
        focused = true
        // 開了「減少動態效果」就不打字，直接顯示全文。
        guard !reduceMotion else {
            revealed = true
            return
        }
        for character in step.body {
            if revealed || Task.isCancelled { return }
            shownCount += 1
            let pause = CoachStyle.punctuation.contains(character) ? CoachStyle.punctuationNanoseconds : CoachStyle.typeNanoseconds
            try? await Task.sleep(nanoseconds: pause)
        }
    }
}
