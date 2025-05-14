import UIKit

extension UIImage {
    /// Returns a new image whose orientation is guaranteed to be `.up`.
    /// UIKit handles any required rotate / flip when we redraw into a fresh context,
    /// so the result is upright without extra maths.
    func fixedOrientation() -> UIImage {
        // If already correct, return self early
        guard imageOrientation != .up else { return self }

        // `size` already accounts for orientation; no need to swap width / height
        let rendered = UIGraphicsImageRenderer(size: size, format: imageRendererFormat)
            .image { _ in
                draw(in: CGRect(origin: .zero, size: size))
            }

        return rendered   // orientation is now `.up`
    }
}
