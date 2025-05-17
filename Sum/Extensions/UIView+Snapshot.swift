import UIKit

extension UIView {
    /// Returns a UIImage snapshot of the view's current hierarchy.
    func asImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { layer.render(in: $0.cgContext) }
    }
    
    /// Returns a snapshot with better memory handling for large views
    func efficientSnapshot() -> UIImage? {
        // Use a smaller scale for very large views
        let scale: CGFloat = bounds.width > 1024 || bounds.height > 1024 ? 0.5 : 1.0
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = isOpaque
        
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let snapshot = renderer.image { context in
            drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        
        return snapshot.compress()
    }
}
