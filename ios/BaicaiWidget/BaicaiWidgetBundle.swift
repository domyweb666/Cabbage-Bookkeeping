import AppIntents
import SwiftUI
import WidgetKit

@main
struct BaicaiWidgetBundle: WidgetBundle {
    var body: some Widget {
        LeftWidget()
        if #available(iOS 18.0, *) {
            AddEntryControl()
        }
    }
}

/// 控制中心的「記一筆」，也能放鎖定畫面下面和動作按鈕。iOS 18 才有。
@available(iOS 18.0, *)
struct AddEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Shared.controlKind) {
            ControlWidgetButton(action: AddEntryIntent()) {
                Label("記一筆", systemImage: "square.and.pencil")
            }
        }
        .displayName("記一筆")
        .description("打開白菜記帳，直接記一筆。")
    }
}
