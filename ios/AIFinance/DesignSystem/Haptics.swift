import UIKit
import VeggieKit

/// 震動只走這裡，每個函式第一行看設定頁的「觸覺回饋」。表上沒有的事件不震。
///
/// | 事件 | 震動 |
/// |---|---|
/// | 記好、改好一筆，訂好預算，存好分類 | success |
/// | 沒存成、最後一個分類取消不掉 | error |
/// | 刪除一筆，刪掉分類 | 輕點 |
/// | 選分類、選圖示、勾常用分類（存成了才震） | selection |
@MainActor
enum Haptics {
    static func saved() {
        guard VeggieHaptics.isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func failed() {
        guard VeggieHaptics.isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func deleted() {
        guard VeggieHaptics.isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selected() {
        guard VeggieHaptics.isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
