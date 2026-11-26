import PhotosUI
import SwiftUI
import UIKit

/// 改一筆裡的收據照片：一排小縮圖，最多三張。點縮圖看大圖，大圖那頁可以刪。
/// 有相機就問要拍照還是從相簿選，沒有相機（模擬器）直接開相簿。
struct ReceiptStrip: View {
    let txnId: UUID

    @State private var photos: [URL] = []
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var shooting = false
    @State private var viewing: ReceiptPage?
    @State private var cameraBlocked = false
    @State private var failure: String?

    private let store = ReceiptPhotos.standard
    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var room: Int { ReceiptPhotos.limit - photos.count }

    var body: some View {
        HStack(spacing: Gap.item) {
            ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                Button {
                    viewing = ReceiptPage(url: url)
                } label: {
                    ReceiptThumb(url: url)
                }
                .buttonStyle(.press)
                .accessibilityLabel(Words.Receipt.photo(index + 1))
                .accessibilityIdentifier("receipt_\(index + 1)")
            }
            if room > 0 { addButton }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metric.touch)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receiptStrip")
        .onAppear(perform: reload)
        .photosPicker(isPresented: $picking, selection: $picked, maxSelectionCount: max(room, 1), matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await add(items) }
        }
        .fullScreenCover(isPresented: $shooting) {
            CameraPicker(isPresented: $shooting) { image in
                if let image { save([image]) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { page in
            ReceiptViewer(url: page.url) { delete(page.url) }
        }
        .alert(Words.Camera.offTitle, isPresented: $cameraBlocked) {
            Button(Words.Camera.openSettings) { CameraAccess.openSettings() }
            Button(Words.cancel, role: .cancel) {}
        } message: {
            Text(Words.Camera.offMessage)
        }
        .alert(
            Words.Receipt.failedTitle,
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(Words.ok, role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if hasCamera {
            Menu {
                Button(Words.Receipt.camera, systemImage: "camera") { shoot() }
                Button(Words.Receipt.library, systemImage: "photo.on.rectangle") { picking = true }
            } label: {
                addLabel
            }
            .accessibilityIdentifier("receiptAdd")
        } else {
            Button {
                picking = true
            } label: {
                addLabel
            }
            .buttonStyle(.press)
            .accessibilityIdentifier("receiptAdd")
        }
    }

    /// 還沒有照片時寫字講清楚；有了就只剩一格加號，排在縮圖後面。
    @ViewBuilder
    private var addLabel: some View {
        if photos.isEmpty {
            Label(Words.Receipt.add, systemImage: "camera")
                .font(Typo.subheadline.font)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .frame(minHeight: Metric.touch)
                .contentShape(Rectangle())
        } else {
            Image(systemName: "plus")
                .font(Typo.body.font.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .frame(width: Metric.touch, height: Metric.touch)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous))
                .accessibilityLabel(Words.Receipt.addMore)
        }
    }

    private func reload() {
        do {
            photos = try store.list(txnId)
        } catch {
            photos = []
            failure = Words.Receipt.loadFailedMessage
        }
    }

    /// 按了「拍照」才問相機權限；之前拒絕過就請人去設定打開。
    private func shoot() {
        guard !CameraAccess.isBlocked else {
            cameraBlocked = true
            return
        }
        shooting = true
    }

    private func add(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items.prefix(room) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    throw ReceiptPhotos.Failure.notAnImage
                }
                images.append(image)
            } catch {
                failure = Words.Receipt.failedMessage
            }
        }
        save(images)
    }

    private func save(_ images: [UIImage]) {
        do {
            for image in images { try store.save(image, for: txnId) }
        } catch {
            failure = Words.Receipt.failedMessage
        }
        reload()
    }

    private func delete(_ url: URL) {
        do {
            try store.delete(url, for: txnId)
        } catch {
            failure = Words.Receipt.deleteFailedMessage
        }
        reload()
    }
}

private struct ReceiptPage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// 一張縮圖。讀檔放到 task 裡，畫面不會卡。
private struct ReceiptThumb: View {
    let url: URL
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
            .fill(Theme.card)
            .frame(width: Metric.touch, height: Metric.touch)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous))
            .task(id: url) {
                let side = Metric.touch * displayScale
                image = await UIImage(contentsOfFile: url.path)?
                    .byPreparingThumbnail(ofSize: CGSize(width: side, height: side))
            }
    }
}

/// 看大圖。右上角可以刪，刪之前問一次，刪了就沒了。
private struct ReceiptViewer: View {
    let url: URL
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(Words.Receipt.viewTitle)
                } else {
                    Text(Words.Receipt.loadFailedMessage)
                        .font(Typo.body.font)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, Gap.screenMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Words.Receipt.viewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Words.done) { dismiss() }
                        .accessibilityIdentifier("receiptDone")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(Words.Receipt.delete, role: .destructive) { confirmDelete = true }
                        .tint(Theme.destructive)
                        .accessibilityIdentifier("receiptDelete")
                }
            }
            .confirmationDialog(Words.Receipt.deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(Words.Receipt.deleteConfirm, role: .destructive) {
                    dismiss()
                    onDelete()
                }
                Button(Words.cancel, role: .cancel) {}
            }
        }
        .tint(Theme.accent)
    }
}

/// 系統相機包一層。拍好或取消都會關掉，取消時交回 nil。
private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDone: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.onDone(info[.originalImage] as? UIImage)
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDone(nil)
            parent.isPresented = false
        }
    }
}
