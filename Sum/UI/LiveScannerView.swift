import SwiftUI
import VisionKit
import Vision
import QuartzCore
import RegexBuilder

@available(iOS 17.0, *)
struct LiveScannerView: UIViewControllerRepresentable {
    @Binding var numberSystem: NumberSystem
    var onNumbersUpdate: @MainActor ([Double]) -> Void
    @Binding var highlights: [CGRect]
    @Binding var highlightConfs: [Float]
    @Binding var cropRect: CGRect?
    var onFixTap: @MainActor (FixCandidate) -> Void = { _ in }
    var onCoordinatorReady: (Coordinator) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(parent: self,
                            highlights: $highlights,
                            highlightConfs: $highlightConfs,
                            onFixTap: onFixTap)
        DispatchQueue.main.async {
            onCoordinatorReady(c)
        }
        return c
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: false,
            // Disable built-in highlights so we can draw our own
            isHighlightingEnabled: false
        )

        context.coordinator.scannerVC = scanner
        scanner.delegate = context.coordinator

        do {
            try scanner.startScanning()
        } catch {
            print("Failed to start scanning: \(error.localizedDescription)")
        }

        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if context.coordinator.system != numberSystem {
            context.coordinator.system = numberSystem
        }
        // Propagate crop rectangle changes
        if context.coordinator.cropRect != cropRect {
            context.coordinator.cropRect = cropRect
        }
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: LiveScannerView
        private var lastSet: Set<Double> = []
        var system: NumberSystem
        var cropRect: CGRect? = nil
        private let highlights: Binding<[CGRect]>
        private let highlightConfs: Binding<[Float]>
        private let onFixTap: (FixCandidate) -> Void
        weak var scannerVC: DataScannerViewController?
        private var tapFixes: [(rect: CGRect, value: Double, conf: Float)] = []

        // Track detection stability across frames
        private var valueCounts: [Double: Int] = [:]
        private var valueData: [Double: (pixel: CGRect, unit: CGRect, conf: Float)] = [:]

        private var lastProcessedTime: CFTimeInterval = 0
        private let frameInterval: CFTimeInterval = 1.0 / 30.0

        init(parent: LiveScannerView,
             highlights: Binding<[CGRect]>,
             highlightConfs: Binding<[Float]>,
             onFixTap: @escaping (FixCandidate) -> Void) {
            self.parent = parent
            self.system = parent.numberSystem
            self.highlights = highlights
            self.highlightConfs = highlightConfs
            self.onFixTap = onFixTap
            super.init()
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removed: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(allItems, in: scanner)
        }

        private func processItems(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            let now = CACurrentMediaTime()
            guard now - lastProcessedTime >= frameInterval else { return }
            lastProcessedTime = now

            tapFixes.removeAll()
            var currentFrame: [(value: Double, pixel: CGRect, unit: CGRect, conf: Float)] = []

            let hostSize = scanner.view?.bounds.size ?? .zero

            // Convert crop rect from unit space to pixel space for filtering
            let cropPixelRect: CGRect? = cropRect.map { r in
                CGRect(x: r.minX * hostSize.width,
                       y: r.minY * hostSize.height,
                       width: r.width * hostSize.width,
                       height: r.height * hostSize.height)
            }

            for item in items {
                if case let .text(textItem) = item {
                    let str = textItem.transcript.trimmingCharacters(in: .whitespaces)
                    guard !str.isEmpty else { continue }

                    var raw = str.replacingOccurrences(of: ",", with: "")
                    if system == .eastern {
                        raw = TextScannerService.normalize(raw)
                    }

                    if let value = Double(raw),
                       value != 0,
                       value > -999999,
                       value < 999999,
                       !value.isInfinite,
                       !value.isNaN {

                        let bounds = textItem.bounds
                        var pixelRect = CGRect(
                            x: bounds.topLeft.x * hostSize.width,
                            y: bounds.topLeft.y * hostSize.height,
                            width: (bounds.topRight.x - bounds.topLeft.x) * hostSize.width,
                            height: (bounds.bottomLeft.y - bounds.topLeft.y) * hostSize.height
                        )

                        pixelRect = pixelRect.insetBy(dx: -20, dy: -20).integral

                        if let cropPx = cropPixelRect, !pixelRect.intersects(cropPx) {
                            continue
                        }

                        // Convert to unit space for the overlay
                        let unitRect = CGRect(
                            x: pixelRect.minX / hostSize.width,
                            y: pixelRect.minY / hostSize.height,
                            width: pixelRect.width / hostSize.width,
                            height: pixelRect.height / hostSize.height
                        )

                        currentFrame.append((value: value,
                                             pixel: pixelRect,
                                             unit: unitRect,
                                             conf: 0.9))
                    }
                }
            }

            // Update detection stability maps
            let currentValues = Set(currentFrame.map { $0.value })
            for val in currentValues {
                valueCounts[val, default: 0] += 1
            }
            for key in Array(valueCounts.keys) {
                if !currentValues.contains(key) {
                    valueCounts[key] = max((valueCounts[key] ?? 0) - 1, 0)
                }
            }
            for (val, count) in valueCounts where count == 0 {
                valueCounts.removeValue(forKey: val)
                valueData.removeValue(forKey: val)
            }
            for data in currentFrame {
                valueData[data.value] = (pixel: data.pixel, unit: data.unit, conf: data.conf)
            }

            let stableValues = valueCounts.filter { $0.value >= 2 }.map { $0.key }
            var rects = [CGRect]()
            var confs = [Float]()
            tapFixes.removeAll()
            for val in stableValues {
                if let data = valueData[val] {
                    rects.append(data.unit)
                    confs.append(data.conf)
                    tapFixes.append((rect: data.pixel, value: val, conf: data.conf))
                }
            }

            let stableSet = Set(stableValues)
            if stableSet != lastSet {
                lastSet = stableSet
                let nums = stableValues.sorted()

                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        parent.onNumbersUpdate(nums)
                        highlights.wrappedValue = rects
                        highlightConfs.wrappedValue = confs
                    }
                }
            }
        }

        func requestFix(at index: Int) {
            guard index < tapFixes.count,
                  let host = scannerVC?.view,
                  let image = host.asImage(),
                  let cg = image.cgImage else {
                return
            }

            let info = tapFixes[index]
            let imageScale = image.scale

            let px = CGRect(
                x: info.rect.minX * imageScale,
                y: info.rect.minY * imageScale,
                width: info.rect.width * imageScale,
                height: info.rect.height * imageScale
            ).integral

            guard px.width > 4 && px.height > 4 else {
                return
            }

            guard let sub = cg.cropping(to: px) else {
                return
            }

            let fix = FixCandidate(image: sub,
                                   rect: info.rect,
                                   suggested: Int(info.value),
                                   confidence: info.conf)
            Task { @MainActor in onFixTap(fix) }
        }
    }
}
