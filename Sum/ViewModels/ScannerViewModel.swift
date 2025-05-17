import SwiftUI
import SwiftData

@MainActor
final class ScannerViewModel: ObservableObject {
    // Store numbers from each source separately
    @Published private(set) var capturedNumbers: [Double] = []    // Document scanner
    @Published private(set) var photoNumbers:    [Double] = []    // Photo picker
    @Published var liveNumbers: [Double] = []
    // Unified published view
    @Published private(set) var numbers: [Double] = []
    @Published private(set) var sum:     Double  = 0
    @Published private(set) var liveSum: Double = 0
    // UI state now lives in NavigationViewModel
    @Published var pickedImage: UIImage?

    // Result presentation
    @Published var croppedImage: UIImage? = nil
    @Published var croppedObservations: [NumberObservation]? = nil
    @Published var isShowingResult = false

    // MARK: - Interactive-fix
    @Published var pendingFixes: [FixCandidate] = []
    @Published var isShowingFixSheet = false
    @Published var currentFix: FixCandidate? = nil

    // MARK: - Alert support
    @Published var showSumAlert = false
    @Published private(set) var lastSum: Double = 0

    // MARK: - Number-system preference (@AppStorage)
    @AppStorage("numberSystem") var storedSystem: NumberSystem = .western {
        didSet { TextScannerService.currentSystem = storedSystem }
    }

    /// استدعاء من DocumentScannerView عند اكتمال المسح
    func handleScanCompleted(_ newNumbers: [Double]) {
        resetNumbers()
        capturedNumbers = newNumbers
        recalcTotals()
    }

    // MARK: - Photo picker
    func startPhotoPick() { }

    // called by new PhotoPickerView
    func handlePickedImage(_ img: UIImage) {
        pickedImage = img    // navVM will toggle cropper
    }

    // called by cropper after OCR on the cropped area
    func handleCroppedNumbers(_ nums: [Double], fixes: [FixCandidate]) {
        resetNumbers()
        photoNumbers   = nums
        // Static scan low-confidence fixes
        if !fixes.isEmpty {
            pendingFixes.append(contentsOf: fixes)
            // Show sheet only if not already shown
            if !isShowingFixSheet { isShowingFixSheet = true }
        }
        // navVM closes cropper afterwards
        if fixes.isEmpty {
            recalcTotals()
        } else {
            recalcTotals()
        }
    }

    /// يُنادى من FixDigitSheet عند انتهاء التصحيحات
    func finishFixes() {
        pendingFixes.removeAll()          // صفّر طابور الإصلاحات
        isShowingFixSheet = false
        recalcTotals()
    }

    // New helper to accept obs + image from cropper
    func receiveCroppedResult(image: UIImage, observations: [NumberObservation]) {
        self.croppedImage        = image
        self.croppedObservations = observations
        self.showSumAlert        = false     // CLOSE any alert to avoid conflict
        self.isShowingResult     = true
        // حفظ السجل إن كان لدينا سياق
        if let context = modelContext {
            persistRecord(in: context)
        }
    }

    /// Recompute totals when any source updates
    private func recalcTotals() {
        numbers = capturedNumbers + photoNumbers
        sum     = numbers.reduce(0, +)

        lastSum      = sum
        showSumAlert = true
    }

    // MARK: - Helpers
    private func resetNumbers() {
        capturedNumbers.removeAll()
        photoNumbers.removeAll()
    }

    // MARK: - Live Scan
    @MainActor
    func startLiveScan() {
        liveNumbers.removeAll()
        liveSum = 0
        currentFix = nil
    }

    /// Update the live-OCR list after the user corrects a digit.
    /// - Parameters:
    ///   - old: The original (possibly wrong) value if known.
    ///   - new: The user-entered corrected value.
    func applyLiveCorrection(old: Double?, new: Double) {
        if let old, let idx = liveNumbers.firstIndex(of: old) {
            liveNumbers[idx] = new          // replace incorrect value
        } else {
            liveNumbers.append(new)         // add if old not found / nil
        }
        liveSum = liveNumbers.reduce(0, +)  // refresh running total shown in overlay
    }

    // MARK: - Persistence
    weak var modelContext: ModelContext?

    private func persistRecord(in context: ModelContext) {
        let rec       = ScanRecord()
        rec.total     = sum
        rec.numbers   = numbers

        if let img = croppedImage,
           let url = try? saveImage(img) {
            rec.imagePath = url.lastPathComponent
        }
        context.insert(rec)
    }

    private func saveImage(_ img: UIImage) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url  = docs.appendingPathComponent(UUID().uuidString + ".jpg")
        try img.jpegData(compressionQuality: 0.8)?.write(to: url)
        return url
    }

    init() {
        TextScannerService.currentSystem = storedSystem    // مزامنة أوليّة
    }
}
