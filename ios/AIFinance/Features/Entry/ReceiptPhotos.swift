import Foundation
import UIKit

// 收據照片：每筆紀錄一個資料夾，放在 App 自己的 Application Support/Receipts/<紀錄 id>/。
// 不進紀錄的資料，所以紀錄的格式不用改；刪紀錄是軟刪除可以復原，照片也留著。
// 照片只存手機，讀寫失敗都往外丟，畫面自己決定怎麼講。

struct ReceiptPhotos {
    /// 一筆最多幾張。
    static let limit = 3
    /// 存檔前把長邊縮到這裡，收據字還看得清楚，一張大約幾百 KB。
    private static let longEdge: CGFloat = 1600
    private static let quality: CGFloat = 0.7

    enum Failure: Error {
        case notAnImage
        case full
    }

    /// 放全部收據的資料夾。
    let root: URL

    /// 測試時資料只放記憶體（-memoryStore），照片也放暫存資料夾，每次開 App 都是空的。
    static let standard: ReceiptPhotos = {
        if AppConfig.current.inMemory {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("Receipts-\(UUID().uuidString)", isDirectory: true)
            return ReceiptPhotos(root: temp)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ReceiptPhotos(root: support.appendingPathComponent("Receipts", isDirectory: true))
    }()

    private func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// 這筆的照片，照加進來的順序。還沒有資料夾就是空的。
    func list(_ id: UUID) throws -> [URL] {
        let dir = folder(id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 壓成 JPEG 存起來，回傳存好的位置。已經三張就丟 full。
    @discardableResult
    func save(_ image: UIImage, for id: UUID) throws -> URL {
        guard try list(id).count < Self.limit else { throw Failure.full }
        guard let data = Self.jpeg(image) else { throw Failure.notAnImage }
        let dir = folder(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 檔名用毫秒數開頭，排起來就是加進來的順序。
        let stamp = String(format: "%015.0f", Date().timeIntervalSince1970 * 1000)
        let url = dir.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8)).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 刪一張。最後一張刪掉時資料夾也拿掉。
    func delete(_ url: URL, for id: UUID) throws {
        try FileManager.default.removeItem(at: url)
        if try list(id).isEmpty {
            try FileManager.default.removeItem(at: folder(id))
        }
    }

    /// 清除所有資料時用：整個 Receipts 資料夾拿掉。
    func eraseAll() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    /// 長邊縮到 1600，壓成 JPEG。本來就比較小的不放大。
    static func jpeg(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, longEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
