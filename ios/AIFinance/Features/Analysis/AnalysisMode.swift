import Foundation

/// 分析頁的四種看法，使用者自己選，選了記在手機上（UserDefaults，沒有紀錄內容）。
/// 一句話＝畫布 K1、還能花＝K2、月曆＝K3、圓餅是多米 2026-11-26 另外要的。
enum AnalysisMode: String, CaseIterable, Identifiable {
    case sentence
    case budget
    case calendar
    case pie

    /// 存在 UserDefaults 的名字。改了舊的選擇會不見，不要改。
    static let storageKey = "analysisMode"

    /// 第一次打開、讀不懂存的值時用。
    static let standard = AnalysisMode.sentence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sentence: Words.AnalysisModes.sentence
        case .budget: Words.AnalysisModes.budget
        case .calendar: Words.AnalysisModes.calendar
        case .pie: Words.AnalysisModes.pie
        }
    }

    /// 畫面測試互不影響：資料只放記憶體時，看法也從預設開始（跟 Preferences.forget 一樣的時機）。
    /// 調度者把 storageKey 併進 Preferences.forget() 之後，這段可以拿掉。
    static let forgetWhenTesting: Void = {
        if AppConfig.current.inMemory { UserDefaults.standard.removeObject(forKey: storageKey) }
    }()
}
