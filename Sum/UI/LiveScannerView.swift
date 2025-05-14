import SwiftUI
import VisionKit

@available(iOS 17.0, *)
struct LiveScannerView: UIViewControllerRepresentable {
    /// Current numeral system (bound to @AppStorage in the VM)
    @Binding var numberSystem: NumberSystem
    /// Continuously streams the set of numbers currently visible.
    var onNumbersUpdate: @MainActor ([Double]) -> Void
    /// Unit-space rects (0…1) – drives highlight overlay
    @Binding var highlights: [CGRect]
    /// Parallel array of confidences (0…1) for each rect
    @Binding var highlightConfs: [Float]
    /// Optional crop rectangle (unit-space 0…1) – when nil → full frame
    @Binding var cropRect: CGRect?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self,
                    highlights: $highlights,
                    confs:      $highlightConfs)
    }

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
        private let highlights: Binding<[CGRect]>
        private let highlightConfs: Binding<[Float]>

        init(parent: LiveScannerView,
             highlights: Binding<[CGRect]>,
             confs:      Binding<[Float]>) {
            self.parent  = parent
            self.system  = parent.numberSystem
            self.regex   = Self.regex(for: system)
            self.highlights = highlights
            self.highlightConfs = confs
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
            var rects  : [CGRect] = []
            var confs  : [Float]  = []

            for item in items {
                guard case let .text(textItem) = item else { continue }
                let str = textItem.transcript

                // --- احسب مستطيل العنصر فى فضاء 0‥1 دائماً ---
                guard let host = scanner.view else { continue }
                let q = item.bounds
                let minX = min(q.topLeft.x,  q.bottomLeft.x,
                               q.topRight.x, q.bottomRight.x)
                let maxX = max(q.topLeft.x,  q.bottomLeft.x,
                               q.topRight.x, q.bottomRight.x)
                let minY = min(q.topLeft.y,  q.topRight.y,
                               q.bottomLeft.y, q.bottomRight.y)
                let maxY = max(q.topLeft.y,  q.topRight.y,
                               q.bottomLeft.y, q.bottomRight.y)
                let boxInView = CGRect(x: minX, y: minY,
                                       width:  maxX - minX,
                                       height: maxY - minY)
                let sz   = host.bounds.size
                let norm = CGRect(x: boxInView.minX / sz.width,
                                  y: boxInView.minY / sz.height,
                                  width : boxInView.width  / sz.width,
                                  height: boxInView.height / sz.height)

                // ✦ فلتر بالقصّ إن وُجد
                if let crop = cropRect, !crop.intersects(norm) { continue }

                // ✦ تجاهل السطور الطويلة
                guard str.count < 40 else { continue }

                // ✦ مطابقة الأرقام
                for m in str.matches(of: regex) {
                    let slice   = String(str[m.range])
                    let cleaned = system == .western
                        ? slice
                        : TextScannerService.normalize(slice)
                    if let v = Double(cleaned) {
                        current.insert(v)
                        rects.append(norm)
                        // DataScanner provides no explicit confidence;
                        // use a simple heuristic: longer match → higher confidence
                        let finalConf: Float = str.count <= 2 ? 0.8 :
                                                   (str.count <= 5 ? 0.6 : 0.4)
                        confs.append(finalConf)
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
                highlights.wrappedValue      = rects
                highlightConfs.wrappedValue  = confs
            }
        }
    }
}
