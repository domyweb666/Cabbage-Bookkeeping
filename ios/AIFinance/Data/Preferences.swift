import Foundation
import VeggieKit

/// 外觀和觸覺回饋由 VeggieKit 存在 UserDefaults，沒有紀錄內容。
@MainActor
enum Preferences {
    /// 回到第一次打開的樣子。
    static func reset() {
        forget()
        Appearance.system.apply()
    }

    /// 畫面還沒出來時用，不碰視窗。
    static func forget() {
        UserDefaults.standard.removeObject(forKey: Appearance.storageKey)
        UserDefaults.standard.removeObject(forKey: VeggieHaptics.storageKey)
    }
}
