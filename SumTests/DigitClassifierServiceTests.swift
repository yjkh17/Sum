import XCTest
@testable import Sum

final class DigitClassifierServiceTests: XCTestCase {
    func makeDigitImage(_ digit: Int) -> CGImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let str = "\(digit)" as NSString
            let textSize = str.size(withAttributes: attributes)
            str.draw(at: CGPoint(x: (size.width - textSize.width)/2,
                                 y: (size.height - textSize.height)/2),
                     withAttributes: attributes)
        }
        return image.cgImage!
    }

    func testPredictDigit() throws {
        DigitClassifierService.preloadModel()
        let digits = [0, 1, 2, 3]
        for d in digits {
            let img = makeDigitImage(d)
            let result = try DigitClassifierService.predictDigit(from: img)
            XCTAssertNotNil(result)
            XCTAssertEqual(result?.0, d)
        }
    }
}
