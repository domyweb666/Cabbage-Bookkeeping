import SwiftUI

/// 三個分頁。順序照多米 2026-11-26（QC-0015）：設定－記帳－分析，記帳在中間、開 app 先看到。
enum Page: Hashable, CaseIterable {
    case settings
    case ledger
    case analysis

    var label: String {
        switch self {
        case .settings: Words.Tab.settings
        case .ledger: Words.Tab.ledger
        case .analysis: Words.Tab.analysis
        }
    }

    var icon: String {
        switch self {
        case .settings: "gearshape.fill"
        case .ledger: "list.bullet"
        case .analysis: "chart.bar.fill"
        }
    }
}

/// 下面的懸浮膠囊分頁列，照豆帳的樣子：離底部安全區多 12 點，比系統分頁列高、字大一號。
/// 系統分頁列貼在最底，多米覺得太下面（QC-0015 #123）。
struct TabBar: View {
    @Binding var page: Page

    var body: some View {
        HStack(spacing: Gap.tight) {
            ForEach(Page.allCases, id: \.self) { tab in
                let isOn = tab == page
                Button {
                    if !isOn { Haptics.selected() }
                    page = tab
                } label: {
                    VStack(spacing: Gap.tight / 2) {
                        Image(systemName: tab.icon)
                            .font(Typo.title3.font.weight(.regular))
                            .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        Text(tab.label)
                            .font(Typo.footnote.font.weight(isOn ? .semibold : .medium))
                            .dynamicTypeSize(...DynamicTypeSize.xLarge)
                            .lineLimit(1)
                    }
                    .foregroundStyle(isOn ? Theme.accentStrong : Theme.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isOn ? Theme.accentSoft : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.row)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("tab_\(tab.label)")
            }
        }
        .padding(Gap.tight * 1.5)
        .frame(width: Metric.tabBarWidth, height: Metric.tabBar)
        .background { plate }
        .padding(.bottom, Metric.tabBarBottom)
        .frame(maxWidth: .infinity)
    }

    /// 影子只掛在膠囊底上，不掛在整組內容上。
    private var plate: some View {
        let shadow = DomyTokens.Elevation.level2
        return Capsule()
            .fill(Theme.card)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}
