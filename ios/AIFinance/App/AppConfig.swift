import FinanceCore
import Foundation

/// 畫面測試用的啟動參數。平常打開 App 時全部是關的。
struct AppConfig {
    /// 資料只放記憶體，關掉就清空（-memoryStore）。
    let inMemory: Bool
    /// 預先放一份假資料（-demo fresh／steady／returning），同時強制用記憶體。
    let demo: DemoData?
    /// 強制深色外觀（-forceDark）。
    let forceDark: Bool
    /// 指定今天是哪一天（-today 2026-11-25）。
    let today: String?
    /// 提示條停留秒數，測試時拉長（-slowToast）。
    let toastSeconds: UInt64

    static let current: AppConfig = {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let demo = value(after: "-demo").flatMap(DemoData.init(rawValue:))
        return AppConfig(
            inMemory: demo != nil || arguments.contains("-memoryStore"),
            demo: demo,
            forceDark: arguments.contains("-forceDark"),
            today: value(after: "-today"),
            toastSeconds: arguments.contains("-slowToast") ? 60 : 5
        )
    }()
}
