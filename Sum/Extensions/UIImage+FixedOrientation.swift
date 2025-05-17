import UIKit

extension UIImage {
    /// Returns an image with correct orientation and optimized memory usage
    func fixedOrientation() -> UIImage {
        // ✦ 0) Automatically resize large images to reduce memory
        let maxSide = max(size.width, size.height)
        if maxSide > 3_000 {
            if let compressed = compress(maxSize: 1024 * 1024) {  // 1MB limit
                return compressed.withFixedOrientation()
            } else {
                return withFixedOrientation()
            }
        }
        
        return withFixedOrientation()
    }
    
    func withFixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
    
    func scaled(to newSize: CGSize) -> UIImage? {
        guard size != newSize else { return self }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // Use exact size
        format.opaque = true  // No transparency needed
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let newImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return newImage
    }
    
    func compress(maxSize: Int = 1024 * 1024) -> UIImage? {  // Default 1MB
        guard let data = jpegData(compressionQuality: 1.0) else { return nil }
        
        if data.count <= maxSize { return self }
        
        // Calculate scale based on desired size
        let scale = sqrt(Double(maxSize) / Double(data.count))
        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        
        return scaled(to: newSize)
    }
}
