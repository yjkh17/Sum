import SwiftUI
import VisionKit

@available(iOS 17.0, *)
struct LiveScannerView: UIViewControllerRepresentable {
    /// Current numeral system (bound to @AppStorage in the VM)
    @Binding var numberSystem: NumberSystem
    /// Continuously streams the set of numbers currently visible.
    var onNumbersUpdate: @MainActor ([Double]) -> Void
    /// Optional crop rectangle (unit-space 0…1) – when nil → full frame
    @Binding var cropRect: CGRect?

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

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.system   = numberSystem
        context.coordinator.cropRect = cropRect     // refresh every frame
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: LiveScannerView
        /// Last set of numbers sent to the view-model — used to avoid
        /// spamming the delegate with identical updates every frame.
        private var lastSet: Set<Double> = []
        // النظام الحالى يُعاد ضبطه في didSet لتحديث الـ regex
        var system: NumberSystem { didSet { regex = Self.regex(for: system) } }
        // current crop (unit space) – nil → whole image
        var cropRect: CGRect? = nil

        init(parent: LiveScannerView) {
            self.parent  = parent
            self.system  = parent.numberSystem
            self.regex   = Self.regex(for: system)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            extractNumbers(from: allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didRemove removed: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            extractNumbers(from: allItems, in: scanner)
        }

        // Cache two compiled regexes, switch instantly on system change
        private static let westR: Regex<Substring> =
            try! Regex(#"[0-9]+(?:\.[0-9]+)?"#)
        private static let eastR: Regex<Substring> =
            try! Regex(#"[٠-٩۰-۹]+(?:\.[٠-٩۰-۹]+)?"#)
        private static func regex(for sys: NumberSystem) -> Regex<Substring> {
            sys == .western ? westR : eastR
        }
        private var regex: Regex<Substring>

        // MARK: - Core extractor
        private func extractNumbers(from items: [RecognizedItem],
                                    in scanner: DataScannerViewController) {
            var current: Set<Double> = []

            for case let .text(textItem) in items {
                let str = textItem.transcript
                // If a crop is active, skip items outside it  (boundingBox is a *method*)
                                if let crop = cropRect {
                                   // frame ⇢ view-space rect; convert إلى 0‥1
                                    let box = textItem.frame
                                    guard let v = scanner.view else { continue }
                                    let sz   = v.bounds.size
                                    let norm = CGRect(x: box.minX / sz.width,
                                                      y: box.minY / sz.height,
                                                      width : box.width  / sz.width,
                                                      height: box.height / sz.height)
                                    guard crop.intersects(norm) else { continue }
                                }
                guard str.count < 40 else { continue }     // قصّ السطور الطويلة
                for m in str.matches(of: regex) {
                    let slice   = String(str[m.range])
                    let cleaned = system == .western
                        ? slice
                        : TextScannerService.normalize(slice)
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
