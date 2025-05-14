import UIKit

extension UIImage {
    /// يُرجِع صورةً موجَّهة `.up`، مع تصغير اختياري للصور الضخمة لتقليل الذاكرة.
    func fixedOrientation() -> UIImage {
        // ✦ 0) تصغير تلقائى للصور الضخمة (اختياري)
        let maxSide = max(size.width, size.height)
        if maxSide > 3_000,
           let thumb = preparingThumbnail(of: CGSize(width: 1_600, height: 1_600)) {
            return thumb.fixedOrientation()          // ثمّ صحّح اتجاهها
        }

        // ✦ 1) إذا كانت أصلاً .up
        guard imageOrientation != .up else { return self }

        // ✦ 2) أعد الرسم فى سياق جديد؛ UIKit يتكفّل بالدوران/العكس
        let renderer = UIGraphicsImageRenderer(size: size, format: imageRendererFormat)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
