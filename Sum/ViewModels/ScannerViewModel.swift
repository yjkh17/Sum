import SwiftUI
import SwiftData

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var isShowingScanner = false
    // Store numbers from each source separately
    @Published private(set) var capturedNumbers: [Double] = []    // Document scanner
    @Published private(set) var photoNumbers:    [Double] = []    // Photo picker
    @Published private(set) var liveNumbers:     [Double] = []    // Live OCR
    // Unified published view
    @Published private(set) var numbers: [Double] = []
    @Published private(set) var sum:     Double  = 0
    // UI state now lives in NavigationViewModel
    @Published var pickedImage: UIImage?

    // Result presentation
    @Published var croppedImage: UIImage? = nil
    @Published var croppedObservations: [NumberObservation]? = nil
    @Published var isShowingResult = false

    // MARK: - Interactive-fix
    @Published var pendingFixes: [FixCandidate] = []
    @Published var isShowingFixSheet = false

    // MARK: - Alert support
    @Published var showSumAlert = false
    @Published private(set) var lastSum: Double = 0

    // MARK: - Number-system preference (@AppStorage)
    @AppStorage("numberSystem") var storedSystem: NumberSystem = .western {
        didSet { TextScannerService.currentSystem = storedSystem }
    }

    /// استدعاء من الـ UI
    func startScan() { }

    /// استدعاء من DocumentScannerView عند اكتمال المسح
    func handleScanCompleted(_ newNumbers: [Double]) {
        resetNumbers()
        capturedNumbers = newNumbers
        recalcTotals()
    }

    // MARK: - Live OCR
    func startLiveScan() {
        resetNumbers()       // navVM toggles sheet
        // CLEAR previous numbers when a new live session starts
    }

    /// Receiving live-update numbers from LiveScannerView
    func handleLiveNumbers(_ nums: [Double]) {
        // Keep only the live feed’s numbers
        capturedNumbers.removeAll()
        photoNumbers.removeAll()
        liveNumbers = nums
        recalcTotals(live: true)
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
        pendingFixes   = fixes
        // navVM closes cropper afterwards
        if fixes.isEmpty {
            recalcTotals()
        } else {
            isShowingFixSheet = true
        }
    }

    /// يُنادى من FixDigitSheet عند انتهاء التصحيحات
    func finishFixes() {
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
    private func recalcTotals(live: Bool = false) {
        numbers = capturedNumbers + photoNumbers + liveNumbers
        sum     = numbers.reduce(0, +)

        guard !live else { return }            // skip alert for video frames
        lastSum      = sum
        showSumAlert = true
    }

    // MARK: - Helpers
    private func resetNumbers() {
        capturedNumbers.removeAll()
        photoNumbers.removeAll()
        liveNumbers.removeAll()
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
