import AVFoundation
import Foundation
import Observation
import Speech

/// 語音輸入（規格 8.1）：Apple 內建辨識，語系 zh-TW，轉成文字後走跟打字同一條路。
@MainActor
@Observable
final class SpeechService {
    enum Status: Equatable {
        case idle
        case listening
        /// 權限被拒、辨識器不可用等。附上給使用者看的說明。
        case unavailable(String)
    }

    private(set) var status: Status = .idle
    /// 即時辨識出來的文字。
    private(set) var transcript = ""

    static let maxSeconds: TimeInterval = 30

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var onFinish: ((String) -> Void)?

    var isListening: Bool { status == .listening }

    /// 開始聽。第一次會詢問麥克風與語音辨識權限。結束（手動停止、超過 30 秒、辨識完成）時回呼最後的文字。
    func start(onFinish: @escaping (String) -> Void) async {
        guard !isListening else { return }
        transcript = ""
        self.onFinish = onFinish

        guard await Self.requestSpeechPermission() else {
            status = .unavailable("沒有語音辨識的權限。可以到「設定 > 白菜記帳」打開，或直接用打字的。")
            return
        }
        guard await Self.requestMicrophonePermission() else {
            status = .unavailable("沒有麥克風的權限。可以到「設定 > 白菜記帳」打開，或直接用打字的。")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("現在沒辦法使用語音辨識，請改用打字。")
            return
        }

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            Self.installTap(on: input, format: format, request: request)
            engine.prepare()
            try engine.start()

            task = Self.startTask(recognizer, request) { [weak self] text, finished in
                Task { @MainActor in
                    guard let self, self.isListening else { return }
                    if let text { self.transcript = text }
                    if finished { self.finish() }
                }
            }
            status = .listening

            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.maxSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            teardown()
            status = .unavailable("麥克風啟動失敗，請再試一次或改用打字。")
        }
    }

    /// 手動停止：保留已辨識的文字。
    func stop() {
        guard isListening else { return }
        finish()
    }

    /// 中途取消：丟掉已辨識的文字。
    func cancel() {
        guard isListening else { return }
        onFinish = nil
        transcript = ""
        finish()
    }

    func clearError() {
        if case .unavailable = status { status = .idle }
    }

    private func finish() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinish
        teardown()
        status = .idle
        callback?(text)
    }

    private func teardown() {
        timeout?.cancel()
        timeout = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        onFinish = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // 音訊與辨識的回呼會在背景執行緒被呼叫，所以放在不屬於主執行緒的函式裡建立。
    nonisolated private static func installTap(
        on input: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func startTask(
        _ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    nonisolated private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    nonisolated private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
