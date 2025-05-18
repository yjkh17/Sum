import UIKit

enum ImageProcessingQuality {
    case low, medium, high
    
    var quality: CGFloat {
        switch self {
        case .low: return 0.3
        case .medium: return 0.5
        case .high: return 0.7
        }
    }
    
    var maxSize: Int {
        switch self {
        case .low: return 512 * 1024     // 512KB
        case .medium: return 1024 * 1024  // 1MB
        case .high: return 2048 * 1024    // 2MB
        }
    }
}

extension UIImage {
    func optimized(quality: ImageProcessingQuality = .medium) throws -> UIImage {
        guard let optimized = self
            .withFixedOrientation()
            .compress(maxSize: quality.maxSize) else {
            throw AppStateManager.AppError.processingFailed("Failed to optimize image")
        }
        
        return optimized
    }
}
