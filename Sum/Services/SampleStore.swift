import UIKit

/// يحفظ قصاصات الأرقام المصحَّحة فى Documents/TrainingSamples
final class SampleStore {
    static let shared = SampleStore(); private init() { }

    private let dir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let url  = docs.appendingPathComponent("TrainingSamples",
                                               isDirectory: true)
        try? FileManager.default.createDirectory(at: url,
                                                 withIntermediateDirectories: true)
        return url
    }()

    /// يحفظ القصاصة بعد تصغيرها إلى ‎28×28‎ لتقليل الحجم
    func save(image cg: CGImage, label: Int) {
        let ui  = UIImage(cgImage: cg)
        let img = ui.preparingThumbnail(of: .init(width: 28, height: 28)) ?? ui
        guard let data = img.pngData() else { return }
        let name = "\(label)_\(UUID().uuidString).png"
        let url = dir.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic) }
        catch { print("[SampleStore] save failed:", error) }
    }
}
