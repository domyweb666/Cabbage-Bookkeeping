import AVFoundation
import FinanceCore
import SwiftUI
import UIKit

// 掃發票：相機對準電子發票證明聯左邊的 QR 碼，讀到就交回記一筆。
// 右邊那個（** 開頭）和別的 QR 碼都不理，繼續等左邊的。

/// 畫面測試用：模擬器沒有相機，啟動參數 -invoiceQR <內容> 讓「掃發票」一按就當作掃到這串。Debug 版才認。
enum InvoiceScanInjection {
    static let text: String? = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-invoiceQR"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
        #else
        return nil
        #endif
    }()
}

/// 相機權限。拍收據和掃發票共用。
enum CameraAccess {
    /// 這台有沒有相機（模擬器沒有）。
    static var exists: Bool { AVCaptureDevice.default(for: .video) != nil }

    /// 被拒絕或被限制了，要請人去設定打開。
    static var isBlocked: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    /// 還沒問過就在這時候問（使用者剛按了相機），回傳能不能用。
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// 掃發票的畫面。讀到左邊那個 QR 碼就呼叫 onFound 一次。
struct InvoiceScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onFound: (String) -> Void

    private enum Status {
        case checking
        case ready
        case blocked
        case noCamera
    }

    @State private var status: Status = .checking

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(Words.Invoice.scan)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Words.cancel) { dismiss() }
                            .accessibilityIdentifier("scanCancel")
                    }
                }
        }
        .tint(Theme.accent)
        .task {
            guard CameraAccess.exists else {
                status = .noCamera
                return
            }
            status = await CameraAccess.request() ? .ready : .blocked
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .checking:
            ProgressView()
        case .ready:
            ZStack(alignment: .bottom) {
                QRCameraView(onFound: onFound)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityHidden(true)
                Text(Words.Invoice.hint)
                    .font(Typo.subheadline.font)
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, Gap.cardPad)
                    .padding(.vertical, Gap.item)
                    .background(Theme.card, in: Capsule())
                    .padding(.bottom, Gap.section)
            }
        case .blocked:
            message(Words.Camera.offMessage, title: Words.Camera.offTitle) {
                Button(Words.Camera.openSettings) { CameraAccess.openSettings() }
                    .font(Typo.body.font.weight(.semibold))
                    .frame(minHeight: Metric.touch)
                    .accessibilityIdentifier("scanOpenSettings")
            }
        case .noCamera:
            message(Words.Camera.missing, title: nil) { EmptyView() }
        }
    }

    private func message<Action: View>(
        _ text: String, title: String?, @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: Gap.group) {
            Image(systemName: "camera")
                .font(Typo.title2.font)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            if let title {
                Text(title)
                    .font(Typo.headline.font)
                    .foregroundStyle(Theme.primaryText)
            }
            Text(text)
                .font(Typo.body.font)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(.horizontal, Gap.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanMessage")
    }
}

/// 相機預覽加 QR 碼辨識。
private struct QRCameraView: UIViewRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start(on: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // layerClass 指定了，這裡一定是預覽層。
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        /// 開關相機會卡住呼叫的那條線，放到自己的佇列。
        private let queue = DispatchQueue(label: "org.domyweb.baicai.scanner")
        private let onFound: (String) -> Void
        private var found = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func start(on layer: AVCaptureVideoPreviewLayer) {
            layer.session = session
            let output = AVCaptureMetadataOutput()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input), session.canAddOutput(output)
            else { return }
            session.beginConfiguration()
            session.addInput(input)
            session.addOutput(output)
            // 要先加進 session 才有可用的種類。
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
            output.setMetadataObjectsDelegate(self, queue: .main)
            session.commitConfiguration()
            let running = session
            queue.async { running.startRunning() }
        }

        func stop() {
            let running = session
            queue.async { running.stopRunning() }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !found else { return }
            for object in metadataObjects {
                guard let code = object as? AVMetadataMachineReadableCodeObject,
                      let text = code.stringValue,
                      InvoiceQR.parse(text) != nil
                else { continue }
                found = true
                stop()
                onFound(text)
                return
            }
        }
    }
}
