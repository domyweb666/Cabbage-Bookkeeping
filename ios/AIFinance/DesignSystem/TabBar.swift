import SwiftUI

/// 四個分頁：設定－記一筆－明細－分析。
/// 多米 2026-11-26 晚上：記一筆要自己一頁、開 app 就停在這頁能記，不用先按一下再跳出來。
/// 原本的「記帳」頁（月份、總額、每天的明細）改叫明細。
enum Page: Hashable, CaseIterable {
    case settings
    case entry
    case ledger
    case analysis

    var label: String {
        switch self {
        case .settings: Words.Tab.settings
        case .entry: Words.Tab.entry
        case .ledger: Words.Tab.ledger
        case .analysis: Words.Tab.analysis
        }
    }

    var icon: String {
        switch self {
        case .settings: "gearshape.fill"
        case .entry: "plus.circle.fill"
        case .ledger: "list.bullet"
        case .analysis: "chart.bar.fill"
        }
    }
}

extension EnvironmentValues {
    /// 這一頁是不是現在選中的分頁。分頁常駐，藏起來的頁用它關掉只該出現一次的東西（提示條）。
    @Entry var isCurrentPage = true
    /// 懸浮分頁列上緣在螢幕上的位置（global 座標）。還沒量到是無限大，什麼都不墊。
    @Entry var tabBarTop: CGFloat = .infinity
}

extension View {
    /// 子頁面底部的按鈕列用。設定頁推進去的頁面拿不到外層替分頁列留的空間，按鈕會被分頁列蓋住
    /// （2026-11-26 截圖 45、50、80、82、89）。量自己的底在哪，被蓋多少就往上墊多少；沒被蓋就是 0。
    func aboveTabBar() -> some View {
        modifier(AboveTabBar())
    }
}

private struct AboveTabBar: ViewModifier {
    @Environment(\.tabBarTop) private var tabBarTop
    @State private var bottom: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, max(0, bottom - tabBarTop))
            // 量的是墊過之後的外框：它貼著底，墊多少都不會動，不會量了又變。
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom = $0 }
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
