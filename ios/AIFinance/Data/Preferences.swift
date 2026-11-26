import Foundation
import VeggieKit

/// 外觀和觸覺回饋由 VeggieKit 存在 UserDefaults，目前在哪一本帳也存這裡。沒有紀錄內容。
@MainActor
enum Preferences {
    private static let ledgerKey = "baicai.currentLedger"

    /// 上次停在哪一本帳。沒存過是 nil，由 LedgerModel 用「我的帳本」。
    static var currentLedger: UUID? {
        get { UserDefaults.standard.string(forKey: ledgerKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: ledgerKey) }
    }

    /// 回到第一次打開的樣子。
    static func reset() {
        forget()
        Appearance.system.apply()
    }

    /// 畫面還沒出來時用，不碰視窗。
    static func forget() {
        UserDefaults.standard.removeObject(forKey: Appearance.storageKey)
        UserDefaults.standard.removeObject(forKey: VeggieHaptics.storageKey)
        UserDefaults.standard.removeObject(forKey: ledgerKey)
        UserDefaults.standard.removeObject(forKey: AnalysisMode.storageKey)
    }
}
