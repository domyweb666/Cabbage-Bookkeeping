import FinanceCore
import SwiftUI
import WidgetKit

// 小工具。讀 App 放在 App Group 的快照，數字交給 FinanceCore 算，跟記帳頁同一套。
// 主畫面小的：標題、數字、記一筆，點了打開記一筆。鎖定畫面：標題和數字，點了打開 App。

struct LeftEntry: TimelineEntry {
    let date: Date
    /// 這一格是哪一天（yyyy-MM-dd），存錢的「過了那天」要用。
    let today: String
    /// 讀不到快照是 nil。
    let figures: HomeFigures?
    /// 目前那本帳在存錢才有。存錢小工具用。
    let savings: SavingsProgress?
}

struct LeftProvider: TimelineProvider {
    /// 今天，加上後面十三個午夜。換日、換月的數字先算好。
    private static let daysAhead = 13

    func placeholder(in context: Context) -> LeftEntry {
        Self.entry(at: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LeftEntry) -> Void) {
        let saved = WidgetBridge.read()
        completion(Self.entry(at: Date(), snapshot: context.isPreview ? saved ?? Self.sample : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<LeftEntry>) -> Void) {
        let snapshot = WidgetBridge.read()
        let entries = Self.dates(from: Date()).map { Self.entry(at: $0, snapshot: snapshot) }
        completion(WidgetKit.Timeline(entries: entries, policy: .atEnd))
    }

    private static func entry(at date: Date, snapshot: WidgetSnapshot?) -> LeftEntry {
        let days = Days.local
        let today = days.day(of: date)
        return LeftEntry(
            date: date, today: today, figures: snapshot?.figures(today: today, days: days), savings: snapshot?.savings
        )
    }

    private static func dates(from now: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: now)
        return [now] + (1...daysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// 加小工具的畫面上，還沒用過的人看到的樣子。
    private static var sample: WidgetSnapshot {
        let today = Days.local.day(of: Date())
        let budget = Budget(month: Days.local.monthStart(of: today), amount: 8500, createdAt: Date())
        let end = Days.local.adding(days: 60, to: today)
        let savings = SavingsProgress(target: 30000, endsOn: end, saved: 17600, hasIncome: true)
        return WidgetSnapshot(today: today, transactions: [], budgets: [budget], fixed: [], savings: savings)
    }
}

struct LeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.widgetKind, provider: LeftProvider()) { entry in
            LeftWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetWords.name)
        .description(WidgetWords.about)
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

private struct LeftWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LeftEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineView(figures: entry.figures)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            RectangularView(figures: entry.figures)
                .containerBackground(for: .widget) { Color.clear }
        default:
            SmallView(figures: entry.figures)
                .containerBackground(for: .widget) { Theme.card }
                .widgetURL(Shared.entryURL)
        }
    }
}

/// 主畫面小的。存錢小工具中尺寸的左半邊也用這個。
struct SmallView: View {
    let figures: HomeFigures?

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            if let figures {
                Text(figures.label)
                    .font(Typo.subheadline.font)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                AmountLabel(amount: figures.amount)
                    .font(Typo.title2.font.monospacedDigit())
                    .foregroundStyle(Theme.accentStrong)
            } else {
                Text(WidgetWords.openApp)
                    .font(Typo.headline.font)
                    .foregroundStyle(Theme.primaryText)
                    .minimumScaleFactor(WidgetLook.minScale)
            }
            Spacer(minLength: 0)
            AddPill()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 整塊小工具都按得到，這顆讓人看得出按了會記一筆。
struct AddPill: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let label = Label(WidgetWords.add, systemImage: "plus")
            .font(Typo.callout.font)
            .lineLimit(1)
            .minimumScaleFactor(WidgetLook.minScale)
            .frame(maxWidth: .infinity, minHeight: Metric.buttonCompact)
        // 主畫面調成單色時，實心的底會把字蓋成一片，改成描邊。
        if renderingMode == .fullColor {
            label
                .foregroundStyle(Theme.onAccent)
                .background(Theme.accent, in: Capsule())
        } else {
            label
                .widgetAccentable()
                .overlay(Capsule().strokeBorder(lineWidth: Metric.hairline).widgetAccentable())
        }
    }
}

/// 鎖定畫面長方形。
private struct RectangularView: View {
    let figures: HomeFigures?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let figures {
                Text(figures.label)
                    .font(.headline)
                    .widgetAccentable()
                AmountLabel(amount: figures.amount)
                    .font(.title2.monospacedDigit())
            } else {
                Text(WidgetWords.openApp)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 鎖定畫面時間上面那一行。
private struct InlineView: View {
    let figures: HomeFigures?

    var body: some View {
        if let figures {
            Text("\(figures.label) \(Money.grouped(figures.amount))")
                .privacySensitive()
        } else {
            Text(WidgetWords.openApp)
        }
    }
}

struct AmountLabel: View {
    let amount: Int

    var body: some View {
        Text(Money.grouped(amount))
            .lineLimit(1)
            .minimumScaleFactor(WidgetLook.minScale)
            .widgetAccentable()
            .privacySensitive()
            .accessibilityLabel(Money.format(amount))
    }
}

enum WidgetLook {
    static let minScale: CGFloat = 0.5
}

/// 小工具上的字。標題（還能花、預算、本月支出）從 FinanceCore 拿。
enum WidgetWords {
    static let name = "還能花多少"
    static let about = "看這個月還能花多少，點一下就記一筆。"
    static let add = "記一筆"
    static let openApp = "打開白菜看"
}
