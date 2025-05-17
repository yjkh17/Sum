import SwiftUI
import VisionKit
import Vision

@available(iOS 17.0, *)
struct LiveScannerView: UIViewControllerRepresentable {
    /// Current numeral system (bound to @AppStorage in the VM)
    @Binding var numberSystem: NumberSystem
    /// Continuously streams the set of numbers currently visible.
    var onNumbersUpdate: @MainActor ([Double]) -> Void
    /// Unit-space rects (0…1) – drives highlight overlay
    @Binding var highlights:     [CGRect]
    /// Parallel array of confidences (0…1) for each rect
    @Binding var highlightConfs: [Float]
    /// Optional crop rectangle (unit-space 0…1) – when nil → full frame
    @Binding var cropRect: CGRect?
    var onFixTap:        @MainActor (FixCandidate)   -> Void = { _ in }
    /// Provide the freshly-created coordinator back to the caller (optional).
    var onCoordinatorReady: (Coordinator) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(parent: self,
                            highlights:     $highlights,
                            highlightConfs: $highlightConfs,
                            onFixTap:       onFixTap)
        DispatchQueue.main.async { onCoordinatorReady(c) }
        return c
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
        private let onFixTap: (FixCandidate) -> Void
        private weak var scannerVC: DataScannerViewController?
        // ---------------------------------------------
        private var tapFixes: [(rect: CGRect, value: Double, conf: Float)] = []
        private static var currentSystem: NumberSystem = .western

        init(parent: LiveScannerView,
             highlights:     Binding<[CGRect]>,
             highlightConfs: Binding<[Float]>,
             onFixTap:       @escaping (FixCandidate) -> Void)
        {
            self.parent          = parent
            self.system          = parent.numberSystem
            self.regex           = Self.regex(for: system)
            self.highlights      = highlights
            self.highlightConfs  = highlightConfs
            self.onFixTap        = onFixTap
            Coordinator.currentSystem = system
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            scannerVC = scanner
            extractNumbers(from: allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didRemove removed: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            scannerVC = scanner
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

            tapFixes.removeAll()

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
                        let finalConf: Float = str.count <= 2 ? 0.8
                                          : (str.count <= 5 ? 0.6 : 0.4)
                        confs.append(finalConf)
                        tapFixes.append((rect: norm, value: v, conf: finalConf))
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
                highlights.wrappedValue     = rects
                highlightConfs.wrappedValue = confs
            }
        }

        private static func processMatch(_ match: Regex<Substring>.Match, in text: String, observation: VNRecognizedTextObservation, imageSize: CGSize) -> (value: Double, rect: CGRect)? {
            var raw = String(text[match.range])
                .replacingOccurrences(of: ",", with: "")
            if currentSystem == .eastern {
                raw = TextScannerService.normalize(raw)
            }
            guard let val = Double(raw) else { return nil }
            
            // Use corners for more accurate perspective
            let topLeft = CGPoint(x: observation.topLeft.x * imageSize.width,
                                y: (1 - observation.topLeft.y) * imageSize.height)
            let topRight = CGPoint(x: observation.topRight.x * imageSize.width,
                                 y: (1 - observation.topRight.y) * imageSize.height)
            let bottomLeft = CGPoint(x: observation.bottomLeft.x * imageSize.width,
                                   y: (1 - observation.bottomLeft.y) * imageSize.height)
            let bottomRight = CGPoint(x: observation.bottomRight.x * imageSize.width,
                                    y: (1 - observation.bottomRight.y) * imageSize.height)
            
            // Calculate bounding rect that encompasses all corners
            let minX = min(topLeft.x, bottomLeft.x, topRight.x, bottomRight.x)
            let maxX = max(topLeft.x, bottomLeft.x, topRight.x, bottomRight.x)
            let minY = min(topLeft.y, bottomLeft.y, topRight.y, bottomRight.y)
            let maxY = max(topLeft.y, bottomLeft.y, topRight.y, bottomRight.y)
            
            let rect = CGRect(x: minX, y: minY, 
                             width: maxX - minX,
                             height: maxY - minY)
            
            return (val, rect)
        }

        // MARK: - Tap-to-Fix
        func requestFix(at index: Int) {
            guard index < tapFixes.count,
                  let host = scannerVC?.view,
                  let cg   = host.asImage()?.cgImage
            else { return }

            let info = tapFixes[index]
            let px = CGRect(x: info.rect.minX * CGFloat(cg.width),
                            y: info.rect.minY * CGFloat(cg.height),
                            width:  info.rect.width  * CGFloat(cg.width),
                            height: info.rect.height * CGFloat(cg.height)).integral
            guard let sub = cg.cropping(to: px) else { return }

            let fix = FixCandidate(image: sub,
                                   rect: info.rect,
                                   suggested: Int(info.value),
                                   confidence: info.conf)
            Task { @MainActor in onFixTap(fix) }
        }
    }
}
