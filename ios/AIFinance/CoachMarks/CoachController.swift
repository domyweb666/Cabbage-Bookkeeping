import Foundation
import Observation

/// 聚光燈引導的狀態：目前第幾步、是否進行中、各目標的位置。
@MainActor
@Observable
final class CoachController {
    /// 「已看過」旗標。日後步驟大改時把 v1 改成 v2，舊使用者會再看一次。
    static let completedKey = "coachTour.v1.completed"

    /// 啟動參數（畫面測試用）：-skipCoach 不自動出現，-forceCoach 不管看過沒都出現。
    private enum Mode { case normal, skip, force }

    let steps = CoachTour.steps
    private(set) var isActive = false
    private(set) var index = 0
    /// 各目標在螢幕上的位置（全域座標），由 .coachTarget 回報。
    private(set) var frames: [String: CGRect] = [:]
    /// 使用者在設定按了「重看教學」，等設定頁收起來就開始。
    private(set) var replayRequested = false

    @ObservationIgnored private var ranThisLaunch = false
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private let mode: Mode

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-skipCoach") {
            mode = .skip
        } else if arguments.contains("-forceCoach") {
            mode = .force
        } else {
            mode = .normal
        }
    }

    var step: CoachStep { steps[index] }
    var isLast: Bool { index == steps.count - 1 }

    /// 現在該不該開始。自動出現只在已經有紀錄、而且還沒看過的時候；重看教學不受限制。
    func wantsStart(hasData: Bool) -> Bool {
        guard !isActive else { return false }
        if replayRequested { return true }
        guard hasData, !ranThisLaunch else { return false }
        switch mode {
        case .skip: return false
        case .force: return true
        case .normal: return !UserDefaults.standard.bool(forKey: Self.completedKey)
        }
    }

    func requestReplay() {
        replayRequested = true
    }

    func start() {
        guard !isActive, !steps.isEmpty else { return }
        replayRequested = false
        ranThisLaunch = true
        index = 0
        isActive = true
        watchTarget()
    }

    /// 前進一步；最後一步之後結束。
    func next() {
        guard isActive else { return }
        if isLast {
            finish()
        } else {
            index += 1
            watchTarget()
        }
    }

    func skip() {
        finish()
    }

    private func finish() {
        waitTask?.cancel()
        waitTask = nil
        isActive = false
        // 走完或跳過才算看過；中途 App 被關掉下次會從頭再來。
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }

    /// 目標等了一下還是沒出現，就跳到下一步，不卡住。
    private func watchTarget() {
        waitTask?.cancel()
        let watched = index
        waitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: CoachStyle.missingTargetNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.isActive, self.index == watched, self.frames[self.step.targetID] == nil else { return }
            self.next()
        }
    }

    // MARK: - 位置回報

    func report(_ id: String, _ frame: CGRect) {
        if frames[id] != frame { frames[id] = frame }
    }

    /// 元件消失時清掉自己回報的位置。別的元件已經用同一個代號蓋掉的話就不動它。
    func forget(_ id: String, _ frame: CGRect) {
        if frames[id] == frame { frames[id] = nil }
    }
}
