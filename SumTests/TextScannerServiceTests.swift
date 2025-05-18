import XCTest
@testable import Sum

final class TextScannerServiceTests: XCTestCase {
    func testNormalizeConvertsEasternDigits() {
        let eastern = "٠١٢٣٤٥٦٧٨٩"
        let normalized = TextScannerService.normalize(eastern)
        XCTAssertEqual(normalized, "0123456789")
    }
}
