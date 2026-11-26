import FinanceCore
import SwiftUI
import WidgetKit

// 存錢的小工具（K13）。跟「還能花」讀同一份快照、同一個時間表，存錢的數字是 App 記帳時算好放進去的。
// 主畫面小的：存錢、還差多少、哪天前多少。中的：左邊還能花（點了記一筆）、右邊存錢。鎖定畫面：一行或兩行。

struct SavingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.savingsWidgetKind, provider: LeftProvider()) { entry in
            SavingsWidgetView(entry: entry)
        }
        .configurationDisplayName(SavingsWidgetWords.name)
        .description(SavingsWidgetWords.about)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct SavingsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LeftEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            SavingsInline(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            SavingsRectangular(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            SavingsMedium(entry: entry)
                .containerBackground(for: .widget) { Theme.card }
        default:
            SavingsSmall(entry: entry)
                .containerBackground(for: .widget) { Theme.card }
        }
    }
}

/// 主畫面小的：沒有在存錢時請人打開 App 開始。
private struct SavingsSmall: View {
    let entry: LeftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            Text(SavingsText.title)
                .font(Typo.subheadline.font)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            if let savings = entry.savings {
                SavingsFigures(savings: savings, today: entry.today)
            } else {
                Text(SavingsWidgetWords.notStarted)
                    .font(Typo.headline.font)
                    .foregroundStyle(Theme.primaryText)
                    .minimumScaleFactor(WidgetLook.minScale)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 還差多少（大字）和哪天前多少。
private struct SavingsFigures: View {
    let savings: SavingsProgress
    let today: String

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            Text(SavingsText.short(savings, today: today))
                .font(Typo.title2.font.monospacedDigit())
                .foregroundStyle(Theme.accentStrong)
                .lineLimit(1)
                .minimumScaleFactor(WidgetLook.minScale)
                .widgetAccentable()
                .privacySensitive()
            Text(SavingsText.widgetDeadline(savings))
                .font(Typo.footnote.font.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(WidgetLook.minScale)
                .privacySensitive()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SavingsText.spoken(savings, today: today))
    }
}

/// 主畫面中的：左邊跟「還能花」小的一樣（點了記一筆），右邊存錢（點了打開 App）。
private struct SavingsMedium: View {
    let entry: LeftEntry

    var body: some View {
        HStack(spacing: Gap.cardPad) {
            left
            Rectangle()
                .fill(Theme.separator)
                .frame(width: Metric.hairline)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Gap.tight) {
                Text(SavingsText.title)
                    .font(Typo.subheadline.font)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let savings = entry.savings {
                    SavingsFigures(savings: savings, today: entry.today)
                } else {
                    Text(SavingsWidgetWords.notStarted)
                        .font(Typo.headline.font)
                        .foregroundStyle(Theme.primaryText)
                        .minimumScaleFactor(WidgetLook.minScale)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var left: some View {
        if let url = Shared.entryURL {
            Link(destination: url) { SmallView(figures: entry.figures) }
        } else {
            SmallView(figures: entry.figures)
        }
    }
}

/// 鎖定畫面長方形：「存錢・還差 12,400」和「1/31 前 30,000」。
private struct SavingsRectangular: View {
    let entry: LeftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let savings = entry.savings {
                Text("\(SavingsText.title)・\(SavingsText.short(savings, today: entry.today))")
                    .font(.headline)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(WidgetLook.minScale)
                    .privacySensitive()
                Text(SavingsText.widgetDeadline(savings))
                    .font(.body.monospacedDigit())
                    .lineLimit(1)
                    .privacySensitive()
            } else {
                Text(SavingsText.title).font(.headline).widgetAccentable()
                Text(SavingsWidgetWords.notStarted).font(.body).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 鎖定畫面時間上面那一行。
private struct SavingsInline: View {
    let entry: LeftEntry

    var body: some View {
        if let savings = entry.savings {
            Text("\(SavingsText.title) \(SavingsText.short(savings, today: entry.today))")
                .privacySensitive()
        } else {
            Text(SavingsWidgetWords.notStarted)
        }
    }
}

enum SavingsWidgetWords {
    static let name = "存錢"
    static let about = "看存錢還差多少。中的那一種左邊是還能花。"
    static let notStarted = "打開白菜開始存錢"
}
