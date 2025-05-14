import UIKit

extension UIImage {
    /// Returns an equivalent image whose CGImage is in `.up` orientation.
    /// (Important for Vision bounding-box maths.)
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up,
              let cg = self.cgImage else { return self }

        let size = CGSize(width: cg.width, height: cg.height)
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }

        let ctx = UIGraphicsGetCurrentContext()!
        // Re-apply orientation transform then draw
        switch imageOrientation {
        // iPhone portrait photos are usually `.right`
        case .right:                     // 90° CCW to become .up
            ctx.rotate(by: .pi/2)
            ctx.translateBy(x: 0, y: -size.height)

        case .left:                      // 90° CW to become .up
            ctx.rotate(by: -.pi/2)
            ctx.translateBy(x: -size.width, y: 0)
        case .down:  ctx.translateBy(x: size.width, y: size.height); ctx.rotate(by: .pi)
        case .upMirrored:
            ctx.translateBy(x: size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        case .downMirrored:
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
        case .leftMirrored:
            ctx.rotate(by: .pi/2)
            ctx.translateBy(x: 0, y: -size.height)
            ctx.scaleBy(x: -1, y: 1)

        case .rightMirrored:
            ctx.rotate(by: -.pi/2)
            ctx.translateBy(x: -size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        default: break
        }
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        let newCG = ctx.makeImage()!
        return UIImage(cgImage: newCG, scale: scale, orientation: .up)
    }
}
