import SwiftUI
import VisionKit

@available(iOS 17.0, *)
struct LiveScannerView: UIViewControllerRepresentable {
    /// Continuously streams the set of numbers currently visible.
    var onNumbersUpdate: @MainActor ([Double]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: LiveScannerView
        private let regex = try! Regex(#"\d+(\.\d+)?"#)

        init(parent: LiveScannerView) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            extractNumbers(from: allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didRemove removed: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            extractNumbers(from: allItems)
        }

        private func extractNumbers(from items: [RecognizedItem]) {
            var nums: [Double] = []
            for item in items {
                guard case let .text(textItem) = item else { continue }
                let str = textItem.transcript
                for match in str.matches(of: regex) {
                    if let value = Double(str[match.range]) {
                        nums.append(value)
                    }
                }
            }
            Task { @MainActor in
                parent.onNumbersUpdate(nums)
            }
        }
    }
}
