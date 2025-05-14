import SwiftUI

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var isShowingScanner = false
    // Store numbers from each source separately
    @Published private(set) var capturedNumbers: [Double] = []    // Document scanner
    @Published private(set) var photoNumbers:    [Double] = []    // Photo picker
    @Published private(set) var liveNumbers:     [Double] = []    // Live OCR
    // Sheets / covers state
    @Published var isShowingLiveScanner  = false
    @Published var isShowingPhotoPicker = false
    @Published var isShowingCropper     = false        // NEW
    @Published var pickedImage: UIImage?               // NEW

    // Result presentation
    @Published var croppedImage: UIImage? = nil
    @Published var croppedObservations: [NumberObservation]? = nil
    @Published var isShowingResult = false

    // Combined view of all numbers
    var numbers: [Double] { capturedNumbers + photoNumbers + liveNumbers }
    var sum: Double       { numbers.reduce(0, +) }

    // MARK: - Alert support
    @Published var showSumAlert = false
    @Published private(set) var lastSum: Double = 0

    /// استدعاء من الـ UI
    func startScan() { isShowingScanner = true }

    /// استدعاء من DocumentScannerView عند اكتمال المسح
    func handleScanCompleted(_ newNumbers: [Double]) {
        resetNumbers()
        capturedNumbers = newNumbers          // replace, not append
        publishSum()
    }

    // MARK: - Live OCR
    func startLiveScan() {
        // CLEAR previous numbers when a new live session starts
        resetNumbers()
        isShowingLiveScanner = true
    }

    /// Receiving live-update numbers from LiveScannerView
    func handleLiveNumbers(_ nums: [Double]) {
        // Keep only the live feed’s numbers
        capturedNumbers.removeAll()
        photoNumbers.removeAll()
        liveNumbers = nums
        publishSum(live: true)
    }

    // MARK: - Photo picker
    func startPhotoPick() { isShowingPhotoPicker = true }

    // called by new PhotoPickerView
    func handlePickedImage(_ img: UIImage) {
        pickedImage          = img           // keep a reference for cropper
        isShowingPhotoPicker = false
        isShowingCropper     = true
    }

    // called by cropper after OCR on the cropped area
    func handleCroppedNumbers(_ nums: [Double]) {
        resetNumbers()
        photoNumbers = nums
        isShowingCropper = false
        publishSum()
    }

    // New helper to accept obs + image from cropper
    func receiveCroppedResult(image: UIImage, observations: [NumberObservation]) {
        self.croppedImage        = image
        self.croppedObservations = observations
        self.showSumAlert        = false     // CLOSE any alert to avoid conflict
        self.isShowingResult     = true
    }

    // helper
    private func publishSum(live: Bool = false) {
        guard !live else { return }            // don't spam alert every video frame
        lastSum = sum
        showSumAlert = true
    }

    // MARK: - Helpers
    private func resetNumbers() {
        capturedNumbers.removeAll()
        photoNumbers.removeAll()
        liveNumbers.removeAll()
    }
}
