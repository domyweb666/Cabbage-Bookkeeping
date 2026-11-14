import Foundation

/// 環境設定。Supabase 的網址與 anon key 在建置時由 xcconfig／CI 寫進 Info.plist，不寫死在程式碼裡。
/// App 裡只會有 anon key；AI 金鑰與 service role key 只存在後端。
struct AppConfig {
    struct Supabase {
        let url: URL
        let anonKey: String
    }

    /// 沒有設定時為 nil，App 會進入示範模式。
    let supabase: Supabase?
    /// 示範模式是否預先放幾筆資料（畫面測試用）。
    let seedDemoData: Bool
    /// 強制用深色外觀（畫面測試用，啟動參數 -forceDark）。
    var forceDark: Bool { ProcessInfo.processInfo.arguments.contains("-forceDark") }

    static let current: AppConfig = {
        let arguments = ProcessInfo.processInfo.arguments
        let forceDemo = arguments.contains("-demoBackend")
        let seed = arguments.contains("-demoSeed")

        let info = Bundle.main.infoDictionary ?? [:]
        let host = (info["SupabaseHost"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (info["SupabaseAnonKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)

        guard !forceDemo, !host.isEmpty, !key.isEmpty, let url = URL(string: "https://\(host)") else {
            return AppConfig(supabase: nil, seedDemoData: seed)
        }
        return AppConfig(supabase: Supabase(url: url, anonKey: key), seedDemoData: false)
    }()
}
