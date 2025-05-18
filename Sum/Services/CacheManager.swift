import Foundation
import UIKit

final class CacheManager {
    static let shared = CacheManager()
    
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.sum.cache", qos: .utility)
    
    private init() {
        // Configure cache limits
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB
        
        // Setup cleanup notification
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    // MARK: - Image Caching
    func cacheImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
        
        // Also save to disk for persistence
        queue.async { [weak self] in
            self?.saveToDisk(image, forKey: key)
        }
    }
    
    func getImage(forKey key: String) -> UIImage? {
        // Try memory cache first
        if let image = cache.object(forKey: key as NSString) {
            return image
        }
        
        // Try disk cache
        return loadFromDisk(forKey: key)
    }
    
    // MARK: - Disk Operations
    private func saveToDisk(_ image: UIImage, forKey key: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let url = cacheDirectory.appendingPathComponent(key)
        
        do {
            try data.write(to: url)
        } catch {
            print("[CacheManager] Failed to save image:", error)
        }
    }
    
    private func loadFromDisk(forKey key: String) -> UIImage? {
        let url = cacheDirectory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        
        // Add back to memory cache
        cache.setObject(image, forKey: key as NSString)
        return image
    }
    
    // MARK: - Cache Management
    private var cacheDirectory: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = urls[0].appendingPathComponent("ImageCache")
        
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir,
                                          withIntermediateDirectories: true)
        }
        
        return cacheDir
    }
    
    func clearCache() {
        // Clear memory cache
        cache.removeAllObjects()
        
        // Clear disk cache
        queue.async { [weak self] in
            guard let self = self else { return }
            try? fileManager.removeItem(at: cacheDirectory)
            try? fileManager.createDirectory(at: cacheDirectory,
                                          withIntermediateDirectories: true)
        }
    }
    
    func handleMemoryWarning() {
        // Only clear memory cache, keep disk cache
        cache.removeAllObjects()
    }
    
    // MARK: - Batch Operations
    func processBatch<T>(_ items: [T], 
                        batchSize: Int = 10,
                        operation: @escaping (T) -> Void) {
        let chunks = items.chunked(into: batchSize)
        
        for chunk in chunks {
            queue.async {
                for item in chunk {
                    operation(item)
                }
            }
        }
    }
    
    struct BatchOperation {
        let key: String
        let image: UIImage
        let quality: ImageProcessingQuality
        let completion: ((UIImage?) -> Void)?
    }
    
    func processBatchOperations(_ operations: [BatchOperation]) {
        let batchSize = 5
        let chunks = operations.chunked(into: batchSize)
        
        for chunk in chunks {
            queue.async { [weak self] in
                autoreleasepool {
                    for operation in chunk {
                        let optimized = try? operation.image.optimized(quality: operation.quality)
                        if let optimized {
                            self?.cacheImage(optimized, forKey: operation.key)
                            
                            DispatchQueue.main.async {
                                operation.completion?(optimized)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helpers
private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
