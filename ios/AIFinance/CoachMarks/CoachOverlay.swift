import SwiftUI

/// 引導的遮罩：全螢幕變暗、目標位置挖洞、洞外圈光暈、說明卡、跳過按鈕。
/// 蓋在主畫面上；彈出視窗（sheet）是另一層，蓋不到，所以步驟不指向彈出視窗裡的東西。
struct CoachOverlay: View {
    @Environment(CoachController.self) private var coach
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastHole: CGRect?

    var body: some View {
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { full in
                layers(insets: insets, size: full.size, origin: full.frame(in: .global).origin)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: coach.index)
        .accessibilityAddTraits(.isModal)
    }

    private func layers(insets: EdgeInsets, size: CGSize, origin: CGPoint) -> some View {
        let step = coach.step
        let target = coach.frames[step.targetID].map {
            $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -step.holePadding, dy: -step.holePadding)
        }
        // 目標還沒回報位置時，洞收成 0 大小，停在上一個洞的中心。
        let rest = lastHole ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        let hole = target ?? CGRect(x: rest.midX, y: rest.midY, width: 0, height: 0)
        let radius = min(step.holeCornerRadius ?? hole.height / 2, hole.height / 2)
        // 目標在下半部時卡片放上面，在上半部時放下面，卡片不會蓋到洞。
        let cardOnTop = hole.midY > size.height / 2
        let dim = colorScheme == .dark ? CoachStyle.dimOpacityDark : CoachStyle.dimOpacity

        return ZStack(alignment: .topTrailing) {
            ZStack {
                ZStack {
                    SpotlightShape(hole: hole, cornerRadius: radius)
                        .fill(Color.black.opacity(dim), style: FillStyle(eoFill: true))
                        // 整片攔截觸控，洞裡面的元件也不能點。
                        .contentShape(Rectangle())
                        .onTapGesture {}

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.accent, lineWidth: CoachStyle.glowWidth)
                        .shadow(color: Theme.accent.opacity(CoachStyle.glowOpacity), radius: CoachStyle.glowRadius)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .opacity(target == nil ? 0 : 1)
                        .allowsHitTesting(false)
                }
                // 開了「減少動態效果」時，洞改成淡出再淡入，不滑動。
                .id(reduceMotion ? coach.index : 0)
                .transition(.opacity)
            }
            .animation(reduceMotion ? .easeOut(duration: CoachStyle.fadeSeconds) : CoachStyle.holeSpring, value: hole)
            .accessibilityHidden(true)

            ZStack {
                if target != nil {
                    VStack(spacing: 0) {
                        if !cardOnTop { Spacer(minLength: 0) }
                        CoachCard(step: step, index: coach.index, total: coach.steps.count) { coach.next() }
                            .frame(maxHeight: size.height * CoachStyle.cardMaxHeightRatio)
                        if cardOnTop { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, CoachStyle.cardMargin)
                    .padding(.top, insets.top + CoachStyle.skipTop + CoachStyle.minimumTap + CoachStyle.skipTop)
                    .padding(.bottom, insets.bottom + CoachStyle.cardMargin)
                    .id(coach.index)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: CoachStyle.cardFadeSeconds), value: coach.index)
            .animation(.easeOut(duration: CoachStyle.cardFadeSeconds), value: target != nil)

            skipButton
                .padding(.top, insets.top + CoachStyle.skipTop)
                .padding(.trailing, CoachStyle.skipTrailing)
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: target, initial: true) { _, new in
            if let new { lastHole = new }
        }
    }

    private var skipButton: some View {
        Button {
            coach.skip()
        } label: {
            HStack(spacing: 4) {
                Text("跳過教學")
                Image(systemName: "xmark")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: CoachStyle.buttonHeight)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
            .frame(minHeight: CoachStyle.minimumTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coachSkip")
        .accessibilityLabel("跳過教學")
    }
}

/// 外框是整個畫面、內框是洞，用 even-odd 規則填色就會挖出洞。
/// 洞的 x、y、寬、高是可動畫的，換步驟時洞才會滑過去而不是瞬間跳過去。
struct SpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.size.width, hole.size.height))
        }
        set {
            hole = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: max(0, newValue.second.first),
                height: max(0, newValue.second.second)
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            let radius = min(cornerRadius, hole.width / 2, hole.height / 2)
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}
