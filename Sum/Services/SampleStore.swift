import UIKit
import CryptoKit

/// Stores and manages corrected digit samples and caches recognition results
final class SampleStore {
    static let shared = SampleStore()
    
    private let dir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                          in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("TrainingSamples",
                                           isDirectory: true)
        try? FileManager.default.createDirectory(at: url,
                                             withIntermediateDirectories: true)
        return url
    }()
    
    // Cache for digit recognition results
    private var recognitionCache = NSCache<NSString, NSNumber>()
    
    // Cache settings
    private let maxCacheSize = 1000
    private let maxImageSize = 28 * 28 * 4 // 28x28 pixels, 4 bytes per pixel
    
    private init() {
        recognitionCache.countLimit = maxCacheSize
        recognitionCache.totalCostLimit = maxCacheSize * maxImageSize
        
        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recognitionCache.removeAllObjects()
        }
    }

    /// Saves a digit sample after resizing to 28×28 to reduce storage
    func saveSample(_ image: UIImage, digit: Int) {
        let img = image.preparingThumbnail(of: .init(width: 28, height: 28)) ?? image
        guard let data = img.pngData() else { return }
        
        // Generate deterministic key for this image
        let key = generateImageKey(data)
        
        // Save to cache
        recognitionCache.setObject(NSNumber(value: digit), forKey: key as NSString)
        
        // Save to disk
        let name = "\(digit)_\(key).png"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("[SampleStore] save failed:", error)
        }
    }
    
    /// Try to get cached recognition result for an image
    func getCachedDigit(for image: UIImage) -> Int? {
        guard let data = image.preparingThumbnail(of: .init(width: 28, height: 28))?
                .pngData() else { return nil }
        
        let key = generateImageKey(data)
        return recognitionCache.object(forKey: key as NSString)?.intValue
    }
    
    private func generateImageKey(_ data: Data) -> String {
        // Generate a reproducible SHA-256 hash of the image data
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Static Interface
extension SampleStore {
    static func save(image: CGImage, as digit: Int) {
        let ui = UIImage(cgImage: image)
        SampleStore.shared.saveSample(ui, digit: digit)
    }
    
    static func getCachedDigit(for cgImage: CGImage) -> Int? {
        let ui = UIImage(cgImage: cgImage)
        return SampleStore.shared.getCachedDigit(for: ui)
    }
}
