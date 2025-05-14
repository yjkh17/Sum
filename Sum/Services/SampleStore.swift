

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

    func save(image cg: CGImage, label: Int) {
        let ui = UIImage(cgImage: cg)
        guard let data = ui.pngData() else { return }
        let name = "\(label)_\(UUID().uuidString).png"
        let url  = dir.appendingPathComponent(name)
        try? data.write(to: url)
    }
}

