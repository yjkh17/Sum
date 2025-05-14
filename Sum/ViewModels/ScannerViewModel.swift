
import SwiftUI

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var isShowingScanner = false
    @Published private(set) var numbers: [Double] = []

    var sum: Double { numbers.reduce(0, +) }

    /// استدعاء من الـ UI
    func startScan() { isShowingScanner = true }

    /// استدعاء من DocumentScannerView عند اكتمال المسح
    func handleScanCompleted(_ newNumbers: [Double]) {
        numbers = newNumbers
    }
}
