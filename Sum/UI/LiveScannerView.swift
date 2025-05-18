import SwiftUI
import VisionKit
import Vision
import QuartzCore  // Add this for CACurrentMediaTime
import RegexBuilder

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
        print("Making coordinator") // Debug
        let c = Coordinator(parent: self,
                            highlights: $highlights,
                            highlightConfs: $highlightConfs,
                            onFixTap: onFixTap)
        print("Coordinator created") // Debug
        DispatchQueue.main.async { 
            print("Calling onCoordinatorReady") // Debug
            onCoordinatorReady(c)
        }
        return c
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        print("\n=== LiveScanner Setup ===")
        print("DataScanner supported: \(DataScannerViewController.isSupported)") // Debug
        print("DataScanner available: \(DataScannerViewController.isAvailable)") // Debug
        
        guard DataScannerViewController.isSupported else {
            print("❌ DataScanner not supported!") // Debug
            fatalError("DataScanner is not supported on this device")
        }

        guard DataScannerViewController.isAvailable else {
            print("❌ DataScanner not available!") // Debug
            fatalError("DataScanner is not available right now")
        }

        print("✅ Creating DataScannerViewController") // Debug
        
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],          // generic text
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,   // safer for Metal
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        
        scanner.delegate = context.coordinator
        
        // Start scanning with error handling
        do {
            print("Starting scanner...") // Debug
            try scanner.startScanning()
            print("Scanner started successfully") // Debug
        } catch {
            print("Failed to start scanning: \(error.localizedDescription)") // Debug
        }
        
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // Only update if the system has actually changed to avoid unnecessary reconfigurations
        if context.coordinator.system != numberSystem {
            print("Updating scanner system from \(context.coordinator.system) to \(numberSystem)") // Debug
            context.coordinator.system = numberSystem
        }
        // cropRect is already a binding and its changes are handled within the coordinator if necessary,
        // or by DataScannerViewController's regionOfInterest if that's how it's used.
        // For now, let's minimize updates here.
        // context.coordinator.cropRect = cropRect
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
        private weak var scannerVC: DataScannerViewController?
        private var tapFixes: [(rect: CGRect, value: Double, conf: Float)] = []
        
        // Frame timing
        private var lastProcessedTime: CFTimeInterval = 0
        private var lastUpdateTime: CFTimeInterval = 0
        private let frameInterval: CFTimeInterval = 1.0 / 30.0  // Target 30fps
        private let updateInterval: CFTimeInterval = 0.1        // Update UI at 10Hz
        
        init(parent: LiveScannerView,
             highlights: Binding<[CGRect]>,
             highlightConfs: Binding<[Float]>,
             onFixTap: @escaping (FixCandidate) -> Void)
        {
            self.parent = parent
            self.system = parent.numberSystem
            self.highlights = highlights
            self.highlightConfs = highlightConfs
            self.onFixTap = onFixTap
            super.init()
        }
        
        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            print("\n➡️ SCANNER: DID_ADD \(added.count) items. Total: \(allItems.count)") // Enhanced log
            for item in added {
                if case let .text(textItem) = item {
                    print("   📄 Added Text: '\(textItem.transcript)' at \(textItem.bounds)")
                } else if case let .barcode(barcodeItem) = item {
                    print("   ║▌║ Added Barcode: \(barcodeItem.payloadStringValue ?? "N/A")")
                }
            }
            processItems(allItems, from: "didAdd", in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didUpdate updated: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            print("\n➡️ SCANNER: DID_UPDATE \(updated.count) items. Total: \(allItems.count)") // Enhanced log
             for item in updated {
                if case let .text(textItem) = item {
                    print("   📄 Updated Text: '\(textItem.transcript)' at \(textItem.bounds)")
                } else if case let .barcode(barcodeItem) = item {
                    print("   ║▌║ Updated Barcode: \(barcodeItem.payloadStringValue ?? "N/A")")
                }
            }
            processItems(allItems, from: "didUpdate", in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didRemove removed: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            print("\n➡️ SCANNER: DID_REMOVE \(removed.count) items. Total: \(allItems.count)") // Enhanced log
            for item in removed {
                if case let .text(textItem) = item {
                    print("   📄 Removed Text: '\(textItem.transcript)'")
                }
            }
            processItems(allItems, from: "didRemove", in: scanner)
        }
        
        // Helper to reduce redundancy
        private func processItems(_ items: [RecognizedItem], from source: String, in scannerVC: DataScannerViewController) {
            let now = CACurrentMediaTime()
            // Store reference to the current scanner view‑controller (needed by requestFix)
            self.scannerVC = scannerVC
            guard now - lastProcessedTime >= frameInterval else {
                // print("Skipping frame for \(source)") // Optional: log frame skips
                return
            }
            lastProcessedTime = now
            // Reset collected tap‑to‑fix rects for this frame
            tapFixes.removeAll()
            autoreleasepool {
                extractNumbers(from: items, in: scannerVC)
            }
        }

        private func extractNumbers(from items: [RecognizedItem],
                                    in scanner: DataScannerViewController) {
            print("\n=== Processing Items ===")
            print("Items count: \(items.count)")
            
            var current = Set<Double>()
            var rects = [CGRect]()
            var confs = [Float]()
            
            let hostSize = scanner.view?.bounds.size ?? .zero
            print("Host size: \(hostSize)")
            
            // Process items
            for item in items {
                if case let .text(textItem) = item {
                    print("\nProcessing text: '\(textItem.transcript)'")
                    
                    // Split multi-line text and process each line
                    let lines = textItem.transcript.components(separatedBy: .newlines)
                    for line in lines {
                        let str = line.trimmingCharacters(in: .whitespaces)
                        
                        // Skip empty lines
                        guard !str.isEmpty else { continue }
                        
                        // Match numbers based on current system
                        let matches = str.matches(of: system == .western ? 
                            try! Regex(#"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#) :
                            try! Regex(#"(?:(?:[٠-٩۰-۹]{1,3}(?:,[٠-٩۰-۹]{3})+|[٠-٩۰-۹]+)(?:\.[٠-٩۰-۹]+)?)"#)
                        )
                        
                        for match in matches {
                            var raw = String(str[match.range])
                                .replacingOccurrences(of: ",", with: "")
                            print("Processing match: '\(raw)'")
                            
                            if system == .eastern {
                                raw = TextScannerService.normalize(raw)
                            }
                            
                            if let value = Double(raw) {
                                // Validate number
                                guard value != 0,
                                      value > -999999,
                                      value < 999999,
                                      !value.isInfinite,
                                      !value.isNaN else {
                                    print("❌ Failed validation")
                                    continue
                                }
                                
                                print("✅ Found valid number: \(value)")
                                
                                // Calculate rect
                                let bounds = textItem.bounds
                                var rect = CGRect(
                                    x: bounds.topLeft.x * hostSize.width,
                                    y: bounds.topLeft.y * hostSize.height,
                                    width: (bounds.topRight.x - bounds.topLeft.x) * hostSize.width,
                                    height: (bounds.bottomLeft.y - bounds.topLeft.y) * hostSize.height
                                )
                                
                                // Add padding and ensure minimum size
                                let minSize: CGFloat = 50
                                let padding: CGFloat = 20
                                
                                rect = rect.insetBy(dx: -padding, dy: -padding)
                                
                                if rect.width < minSize {
                                    let expand = (minSize - rect.width) / 2
                                    rect.origin.x -= expand
                                    rect.size.width = minSize
                                }
                                if rect.height < minSize {
                                    let expand = (minSize - rect.height) / 2
                                    rect.origin.y -= expand
                                    rect.size.height = minSize
                                }
                                
                                // Clamp to view bounds
                                rect.origin.x = max(0, min(rect.origin.x, hostSize.width - rect.width))
                                rect.origin.y = max(0, min(rect.origin.y, hostSize.height - rect.height))
                                
                                rect = rect.integral
                                
                                // Calculate confidence
                                let confidence: Float = str.count <= 2 ? 0.95
                                                   : str.count <= 5 ? 0.85
                                                   : 0.75
                                
                                current.insert(value)
                                rects.append(rect)
                                confs.append(confidence)
                                tapFixes.append((rect: rect, value: value, conf: confidence))
                            }
                        }
                    }
                }
            }
            
            // Throttle UI updates to 10 Hz and use updateInterval
            let now = CACurrentMediaTime()
            let hasChanged = current != lastSet
            guard hasChanged || now - lastUpdateTime >= updateInterval else { return }

            lastSet = current
            lastUpdateTime = now
            let nums = Array(current).sorted()

            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.15)) {
                    parent.onNumbersUpdate(nums)
                    highlights.wrappedValue = rects
                    highlightConfs.wrappedValue = confs
                }
            }
        }

        // MARK: - Tap-to-Fix
        func requestFix(at index: Int) {
            guard index < tapFixes.count,
                  let host = scannerVC?.view,
                  let image = host.asImage(), // Get UIImage first
                  let cg = image.cgImage       // Then get CGImage
            else { 
                print("❌ Error: Could not get host view or image for fix.")
                return 
            }

            let info = tapFixes[index] // info.rect is in points
            let imageScale = image.scale // Get the scale of the captured image (e.g., 1.0, 2.0, 3.0)

            // Convert rect from points to pixels using the image's scale
            let px = CGRect(
                x: info.rect.minX * imageScale,
                y: info.rect.minY * imageScale,
                width: info.rect.width * imageScale,
                height: info.rect.height * imageScale
            ).integral // Make it integral for pixel boundaries

            // Add a check for the size of px before cropping
            // Vision requires dimensions to be > 2 pixels. Let's be a bit safer.
            guard px.width > 4 && px.height > 4 else {
                 print("❌ Error: Crop rectangle for fix is too small in pixels: \(px). Original point rect: \(info.rect)")
                 return
            }

            guard let sub = cg.cropping(to: px) else {
                print("❌ Error: Failed to crop image for fix. Pixel crop rect: \(px), CGImage size: \(cg.width)x\(cg.height)")
                return
            }

            let fix = FixCandidate(image: sub,
                                   rect: info.rect, // This rect is still in points, which is fine for FixCandidate UI
                                   suggested: Int(info.value),
                                   confidence: info.conf)
            Task { @MainActor in onFixTap(fix) }
        }
    }
}
