import SwiftUI

extension View {
    /// 讓這個元件可以被聚光燈照亮。代號對應 CoachStep.targetID；傳 nil 就不回報。
    func coachTarget(_ id: String?) -> some View {
        modifier(CoachTargetModifier(id: id))
    }
}

/// 把元件在螢幕上的位置回報給 CoachController。
/// 規格原本用 anchorPreference 往上傳，但時間軸是 List，列裡的 preference 傳不傳得出來沒辦法在這台機器上驗，
/// 所以改成直接量全域座標。捲動、旋轉、字級改變時位置一樣會跟著更新。
private struct CoachTargetModifier: ViewModifier {
    @Environment(CoachController.self) private var coach
    let id: String?

    func body(content: Content) -> some View {
        content.background {
            if let id {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear
                        .onAppear { coach.report(id, frame) }
                        .onChange(of: frame) { _, new in coach.report(id, new) }
                        .onDisappear { coach.forget(id, frame) }
                }
            }
        }
    }
}
