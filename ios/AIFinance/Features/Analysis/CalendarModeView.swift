import FinanceCore
import SwiftUI

/// 看法「月曆」（畫布 K3）：整個月一格一天，越深花越多，點一天看那天的紀錄；下面比這週跟上週。
/// 深淺照跟最多那天比，切成三級；固定支出不算，不然房租那天永遠最深。
struct CalendarModeView: View {
    @Environment(LedgerModel.self) private var model

    let report: MonthReport

    @State private var opened: DayPick?

    var body: some View {
        let daily = Analysis.daily(
            month: report.month, today: model.today, transactions: model.transactions, days: model.days
        )
        VStack(alignment: .leading, spacing: Gap.section) {
            calendarCard(daily)
            // 上週同幾天只有這個月看得到；以前的月份不比週。
            if report.isCurrent,
               let week = Analysis.weekComparison(today: model.today, transactions: model.transactions, days: model.days) {
                weekCard(week)
            }
        }
        .sheet(item: $opened) { DaySheet(day: $0.day) }
    }

    // MARK: - 月曆

    private func calendarCard(_ daily: DailySpending) -> some View {
        let lead = model.days.weekday(of: report.month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: CalendarSize.gap), count: Days.weekdayNames.count)
        return VStack(alignment: .leading, spacing: Gap.group) {
            AnalysisCardTitle(AnalysisText.calendarTitle)
            AnalysisAnswer(
                AnalysisText.dailyAnswer(daily) ?? AnalysisText.headline(report), id: "calendarAnswer"
            )
            LazyVGrid(columns: columns, spacing: CalendarSize.gap) {
                ForEach(Days.weekdayNames, id: \.self) { name in
                    Text(name)
                        .font(Typo.caption.font)
                        .foregroundStyle(Theme.secondaryText)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .accessibilityHidden(true)
                }
                ForEach(0..<lead, id: \.self) { _ in
                    Color.clear.frame(height: Metric.touch).accessibilityHidden(true)
                }
                ForEach(daily.days) { item in
                    dayCell(item, level: daily.level(of: item))
                }
            }
            legend
            if let text = AnalysisText.dailyHidden(daily.hidden) { AnalysisSmall(text) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("calendarCard")
    }

    private func dayCell(_ item: DaySpend, level: Int) -> some View {
        let isToday = item.day == model.today
        let shape = RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
        return Button {
            opened = DayPick(day: item.day)
        } label: {
            Text("\(item.number)")
                .font(Typo.caption.font.monospacedDigit())
                // 格子大小固定，數字放大到這裡為止；讀螢幕的人聽得到完整的日期和金額。
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .foregroundStyle(item.isFuture ? Theme.tertiaryText : CalendarSize.text(level))
                .frame(maxWidth: .infinity, minHeight: Metric.touch)
                .background(item.isFuture ? Color.clear : CalendarSize.fill(level), in: shape)
                .overlay {
                    if isToday { shape.strokeBorder(Theme.accent, lineWidth: CalendarSize.todayRing) }
                }
                .contentShape(shape)
        }
        .buttonStyle(.press)
        .disabled(item.isFuture)
        .accessibilityLabel(Words.AnalysisModes.day(item))
        .accessibilityIdentifier("calendarDay_\(item.number)")
    }

    private var legend: some View {
        HStack(spacing: Gap.item) {
            AnalysisSmall(AnalysisText.calendarLow)
            HStack(spacing: CalendarSize.gap) {
                ForEach(0...DailySpending.levels, id: \.self) { level in
                    RoundedRectangle(cornerRadius: CalendarSize.swatchRadius, style: .continuous)
                        .fill(CalendarSize.fill(level))
                        .frame(width: CalendarSize.swatch, height: CalendarSize.swatch)
                }
            }
            .accessibilityHidden(true)
            AnalysisSmall(AnalysisText.calendarHigh)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 這週跟上週

    private func weekCard(_ week: WeekComparison) -> some View {
        let scale = max(1, week.thisAmount, week.lastAmount)
        let todayName = Days.weekdayNames[model.days.weekday(of: model.today)]
        return VStack(alignment: .leading, spacing: Gap.group) {
            AnalysisCardTitle(AnalysisText.weekTitle)
            AnalysisAnswer(AnalysisText.week(week, todayName: todayName), id: "weekAnswer")
            weekBar(AnalysisText.weekLabel(week.thisWeek, isThisWeek: true), amount: week.thisAmount, scale: scale)
            weekBar(AnalysisText.weekLabel(week.lastWeek, isThisWeek: false), amount: week.lastAmount, scale: scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func weekBar(_ label: String, amount: Int, scale: Int) -> some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            HStack {
                Text(label).foregroundStyle(Theme.primaryText)
                Spacer(minLength: Gap.item)
                Text(Money.format(amount)).foregroundStyle(Theme.primaryText)
            }
            .font(Typo.subheadline.font.monospacedDigit())
            PlainBar(value: amount, scale: scale, isHollow: false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Words.AnalysisModes.weekBar(label: label, amount: amount))
    }
}

/// 月曆上點的那一天。
struct DayPick: Identifiable {
    let day: String

    var id: String { day }
}

/// 月曆格子的尺寸和深淺，只有這個檔用。
private enum CalendarSize {
    static let gap: CGFloat = 4
    static let todayRing: CGFloat = 2
    static let swatch: CGFloat = 12
    static let swatchRadius: CGFloat = 3

    /// 越深花越多。深色外觀反過來是越亮花越多，一樣是跟底色差越多越多。
    static func fill(_ level: Int) -> Color {
        switch level {
        case 0: Theme.separator
        case 1: Theme.tertiaryText
        case 2: Theme.secondaryText
        default: Theme.primaryText
        }
    }

    /// 格子上的數字：深的格子用卡片的顏色才看得清楚。
    static func text(_ level: Int) -> Color {
        level >= 2 ? Theme.card : Theme.primaryText
    }
}

/// 某一天的每一筆，點一筆打開來改。
struct DaySheet: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let day: String

    @State private var editing: Txn?

    var body: some View {
        let section = model.sections.first { $0.day == day }
        let items = section?.items ?? []
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyMessage(title: Words.AnalysisModes.dayEmptyTitle, message: Words.AnalysisModes.dayEmptyMessage)
                } else {
                    List {
                        Section {
                            ForEach(items) { item in
                                Button {
                                    editing = item
                                } label: {
                                    TxnRow(item: item)
                                }
                                .buttonStyle(.row)
                            }
                        } header: {
                            Text(Words.AnalysisModes.dayHeader(count: items.count, total: section?.expenseTotal ?? 0))
                                .font(Typo.footnote.font.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                                .textCase(nil)
                                .accessibilityIdentifier("dayHeader")
                        }
                    }
                    .ledgerList()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.title(for: day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Words.done) { dismiss() }
                        .accessibilityIdentifier("daySheetDone")
                }
            }
            .sheet(item: $editing) { EntrySheet(mode: .edit($0)) }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
