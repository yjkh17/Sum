
import UIKit

extension UIView {
    /// Returns a UIImage snapshot of the view’s current hierarchy.
    func asImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { layer.render(in: $0.cgContext) }
    }
}
