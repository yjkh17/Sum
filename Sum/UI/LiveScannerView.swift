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
            var current = Set<Double>()
            var rects = [CGRect]()
            var confs = [Float]()

            let hostSize = scanner.view?.bounds.size ?? .zero

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
                        var rect = CGRect(
                            x: bounds.topLeft.x * hostSize.width,
                            y: bounds.topLeft.y * hostSize.height,
                            width: (bounds.topRight.x - bounds.topLeft.x) * hostSize.width,
                            height: (bounds.bottomLeft.y - bounds.topLeft.y) * hostSize.height
                        )

                        rect = rect.insetBy(dx: -20, dy: -20).integral

                        current.insert(value)
                        rects.append(rect)
                        confs.append(0.9)
                        tapFixes.append((rect: rect, value: value, conf: 0.9))
                    }
                }
            }

            if current != lastSet {
                lastSet = current
                let nums = Array(current).sorted()

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
