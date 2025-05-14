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
        /// Last set of numbers sent to the view-model — used to avoid
        /// spamming the delegate with identical updates every frame.
        private var lastSet: Set<Double> = []

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

        private static func currentRegex() -> Regex<Substring> {
            switch TextScannerService.currentSystem {
            case .western: return try! Regex(#"[0-9]+(\.[0-9]+)?"#)
            case .eastern: return try! Regex(#"[٠-٩۰-۹]+(\.[٠-٩۰-۹]+)?"#)
            }
        }

        private func extractNumbers(from items: [RecognizedItem]) {
            var current: Set<Double> = []

            for case let .text(textItem) in items {
                let str = textItem.transcript
                for m in str.matches(of: Self.currentRegex()) {
                    let slice   = String(str[m.range])
                    let cleaned = TextScannerService.currentSystem == .eastern
                        ? TextScannerService.normalize(slice)
                        : slice
                    if let v = Double(cleaned) {
                        current.insert(v)
                    }
                }
            }

            // Only emit if something actually changed
            guard current != lastSet else { return }
            lastSet = current

            // Stable order for UI
            let nums = Array(current).sorted()
            Task { @MainActor in
                parent.onNumbersUpdate(nums)
            }
        }
    }
}
