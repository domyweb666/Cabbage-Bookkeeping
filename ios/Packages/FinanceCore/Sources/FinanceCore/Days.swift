import Foundation

/// 日期處理一律明確指定時區。「哪一天」用 yyyy-MM-dd 字串表示，跟後端一致。
public struct Days: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar

    public static let taipei = Days(timeZone: TimeZone(identifier: "Asia/Taipei")!)

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "zh_TW")
        self.calendar = c
    }

    /// 某個時間點在這個時區是哪一天。
    public func day(of date: Date) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    /// yyyy-MM-dd → 那一天中午（取中午避免日光節約或換日邊界的問題）。
    public func date(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        c.hour = 12
        guard let d = calendar.date(from: c), self.day(of: d) == day else { return nil }
        return d
    }

    public func adding(days: Int, to day: String) -> String {
        guard let d = date(of: day), let moved = calendar.date(byAdding: .day, value: days, to: d) else { return day }
        return self.day(of: moved)
    }

    /// 該月第一天。
    public func monthStart(of day: String) -> String {
        String(day.prefix(7)) + "-01"
    }

    public func adding(months: Int, toMonthOf day: String) -> String {
        guard let d = date(of: monthStart(of: day)),
              let moved = calendar.date(byAdding: .month, value: months, to: d) else { return day }
        return monthStart(of: self.day(of: moved))
    }

    /// "2026-11-15" → "2026 年 11 月"
    public func monthTitle(of day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return day }
        return "\(parts[0]) 年 \(parts[1]) 月"
    }

    /// 時間軸的日期標題：今天、昨天、11 月 13 日 週五；跨年才帶年份。
    public func sectionTitle(for day: String, today: String) -> String {
        if day == today { return "今天" }
        if day == adding(days: -1, to: today) { return "昨天" }
        guard let d = date(of: day) else { return day }
        let p = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        let base = "\(p.month!) 月 \(p.day!) 日 週\(weekdays[(p.weekday! - 1) % 7])"
        return day.prefix(4) == today.prefix(4) ? base : "\(p.year!) 年 \(base)"
    }

    /// 傳給後端的時間字串（ISO 8601，帶時區偏移）。
    public func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = timeZone
        return f.string(from: date)
    }
}
