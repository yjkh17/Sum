import SwiftUI
import SwiftData

@MainActor
final class ScannerViewModel: ObservableObject {
    // Store numbers from each source separately
    @Published private(set) var capturedNumbers: [Double] = []    // Document scanner
    @Published private(set) var photoNumbers: [Double] = []    // Photo picker
    @Published var liveNumbers: [Double] = []
    // Unified published view
    @Published private(set) var numbers: [Double] = []
    @Published private(set) var sum:     Double  = 0
    @Published private(set) var liveSum: Double = 0
    // UI state now lives in NavigationViewModel
    @Published var pickedImage: UIImage?

    // Result presentation (lazy loaded)
    private var _croppedImage: UIImage?
    private var _croppedObservations: [NumberObservation]?
    
    var croppedImage: UIImage? {
        get { _croppedImage }
        set { _croppedImage = newValue }
    }
    
    var croppedObservations: [NumberObservation]? {
        get { _croppedObservations }
        set { _croppedObservations = newValue }
    }
    
    @Published var isShowingResult = false

    // MARK: - Interactive-fix (lazy loaded)
    private var _pendingFixes: [FixCandidate] = []
    @Published var isShowingFixSheet = false
    @Published var currentFix: FixCandidate? = nil
    
    var pendingFixes: [FixCandidate] {
        get { _pendingFixes }
        set { _pendingFixes = newValue }
    }

    // MARK: - Alert support
    @Published var showSumAlert = false
    @Published private(set) var lastSum: Double = 0

    // MARK: - Number-system preference (@AppStorage)
    @AppStorage("numberSystem") var storedSystem: NumberSystem = .western {
        didSet { TextScannerService.currentSystem = storedSystem }
    }

    private let previewQuality: ImageProcessingQuality = .medium
    private let archiveQuality: ImageProcessingQuality = .high
    
    private let croppedCache = NSCache<NSString, UIImage>()
    
    private func cacheImage(_ image: UIImage, withKey key: String) {
        croppedCache.setObject(image, forKey: key as NSString)
    }
    
    private func getCachedImage(forKey key: String) -> UIImage? {
        return croppedCache.object(forKey: key as NSString)
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
        
        Task { @MainActor in
            AppStateManager.shared.beginBackgroundTask()
            defer { 
                AppStateManager.shared.endBackgroundTask()
                processingState = .idle
            }
            
            processingState = .processing(progress: 0)
            
            do {
                photoNumbers = nums
                updateProgress(0.3)
                
                if !fixes.isEmpty {
                    let fixImages = fixes.map { ($0.image, UUID().uuidString) }
                    processBatchImages(fixImages.map { (UIImage(cgImage: $0.0), $0.1) })
                    
                    _pendingFixes = fixes
                    if !isShowingFixSheet {
                        isShowingFixSheet = true
                    }
                }
                updateProgress(0.7)
                recalcTotals()
                updateProgress(1.0)
            } catch {
                processingState = .error(error.localizedDescription)
                AppStateManager.shared.handleError(error)
            }
        }
    }

    /// يُنادى من FixDigitSheet عند انتهاء التصحيحات
    func finishFixes() {
        _pendingFixes.removeAll()          // صفّر طابور الإصلاحات
        isShowingFixSheet = false
        recalcTotals()
    }

    // New helper to accept obs + image from cropper
    func receiveCroppedResult(image: UIImage, observations: [NumberObservation]) {
        // Use preview quality for UI
        _croppedImage = image.optimized(quality: previewQuality)
        _croppedObservations = observations
        showSumAlert = false
        isShowingResult = true
        
        // Archive with higher quality in background
        if let context = modelContext {
            Task.detached(priority: .background) { [weak self] in
                await self?.persistRecord(image: image, in: context)
            }
        }
    }

    @MainActor
    private func persistRecord(image: UIImage, in context: ModelContext) {
        let rec = ScanRecord()
        rec.total = sum
        rec.numbers = numbers
        
        // Save high quality version for archive
        let archiveImage = image.optimized(quality: archiveQuality)
        if let url = try? saveImage(archiveImage) {
            rec.imagePath = url.lastPathComponent
        }
        
        context.insert(rec)
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

    // MARK: - Memory Management
    private var taskQueue = OperationQueue()
    private var activeOperations: Set<Operation> = []
    
    // Make ProcessingState public for ContentView access
    public enum ProcessingState {
        case idle
        case processing(progress: Double)
        case error(String)
        
        var isProcessing: Bool {
            if case .processing = self { return true }
            return false
        }
        
        var progress: Double {
            if case .processing(let progress) = self { return progress }
            return 0
        }
    }
    
    @Published private(set) var processingState: ProcessingState = .idle
    
    private func updateProgress(_ progress: Double) {
        Task { @MainActor in
            processingState = .processing(progress: progress)
        }
    }
    
    private var processingTask: Task<Void, Error>?
    private let processingQueue = DispatchQueue(label: "com.sum.imageProcessing", qos: .userInitiated)
    private var processingOperation: Operation?
    
    private func handleProcessingError(_ error: Error) {
        Task { @MainActor in
            processingState = .error(error.localizedDescription)
            AppStateManager.shared.handleError(error)
            
            // Auto-reset error state after delay
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000) // 3 seconds
            if case .error = processingState {
                processingState = .idle
            }
        }
    }
    
    private func processScan(_ image: UIImage) async throws {
        let appState = AppStateManager.shared
        
        // Cancel any existing task
        processingTask?.cancel()
        
        // Create new task
        processingTask = Task { @MainActor in
            do {
                appState.beginBackgroundTask()
                defer { 
                    appState.endBackgroundTask()
                    if case .processing = processingState {
                        processingState = .idle
                    }
                }
                
                processingState = .processing(progress: 0)
                
                let optimizedImage = image.optimized(quality: .medium)
                updateProgress(0.3)
                
                try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
                    guard let self = self else {
                        continuation.resume(throwing: AppStateManager.AppError.processingFailed("Self is nil"))
                        return
                    }
                    
                    self.updateProgress(0.5)
                    
                    appState.enqueueTask { @Sendable in
                        Task { @MainActor in
                            do {
                                if Task.isCancelled {
                                    continuation.resume(throwing: AppStateManager.AppError.taskCancelled)
                                    return
                                }
                                
                                self.updateProgress(0.7)
                                try await self.processOptimizedImage(optimizedImage)
                                self.updateProgress(1.0)
                                continuation.resume()
                            } catch {
                                self.handleProcessingError(error)
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            } catch {
                handleProcessingError(error)
                throw error
            }
        }
        
        // Wait for task completion
        try await processingTask?.value
    }
    
    @MainActor
    private func processOptimizedImage(_ image: UIImage) async throws {
        guard !Task.isCancelled else {
            throw AppStateManager.AppError.taskCancelled
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let operation = BlockOperation { @Sendable in
                autoreleasepool {
                    do {
                        // Example processing that could throw
                        if image.size.width < 1 || image.size.height < 1 {
                            continuation.resume(throwing: AppStateManager.AppError.processingFailed("Invalid image dimensions"))
                            return
                        }
                        
                        // Process image in autorelease pool to manage memory
                        _ = image.optimized(quality: .medium)
                        continuation.resume()
                        
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Cancel previous operation if exists
            processingOperation?.cancel()
            processingOperation = operation
            
            // Add completion handler
            operation.completionBlock = { [weak operation] in
                guard let operation = operation else { return }
                if operation.isCancelled {
                    continuation.resume(throwing: AppStateManager.AppError.taskCancelled)
                }
            }
            
            // Start processing
            processingQueue.async { operation.start() }
        }
    }
    
    private func processBatchImages(_ images: [(image: UIImage, id: String)]) {
        guard !images.isEmpty else { return }
        
        processingState = .processing(progress: 0)
        
        let totalCount = Double(images.count)
        var processedCount = 0
        
        let operations = images.map { (image, id) in
            CacheManager.BatchOperation(
                key: id,
                image: image,
                quality: .medium
            ) { [weak self] optimized in
                guard let self = self else { return }
                
                processedCount += 1
                
                Task { @MainActor in
                    // Update progress
                    self.updateProgress(Double(processedCount) / totalCount)
                    
                    // Update UI with optimized image
                    if let optimized = optimized {
                        self.updateProcessedImage(optimized, forId: id)
                    }
                    
                    // Check if all processing is complete
                    if processedCount == images.count {
                        self.processingState = .idle
                        self.finishProcessing()
                    }
                }
            }
        }
        
        AppStateManager.shared.beginBackgroundTask()
        CacheManager.shared.processBatchOperations(operations)
    }
    
    private func updateProcessedImage(_ image: UIImage, forId id: String) {
        // Update cached image
        if let croppedImage = image.compress(maxSize: 512 * 1024) {
            _croppedImage = croppedImage
        }
        
        // Trigger UI update if needed
        withAnimation {
            isShowingResult = true
        }
    }
    
    private func finishProcessing() {
        AppStateManager.shared.endBackgroundTask()
        
        // Clean up temporary resources
        pickedImage = nil
        
        // Show results
        if !numbers.isEmpty {
            showSumAlert = true
        }
    }

    private func setupQueue() {
        taskQueue.maxConcurrentOperationCount = 1
        taskQueue.qualityOfService = .userInitiated
    }
    
    @objc private func handleMemoryWarning() {
        // Cancel any pending operations
        taskQueue.cancelAllOperations()
        activeOperations.removeAll()
        
        // Clear temporary resources
        _croppedImage = nil
        _croppedObservations = nil
        pickedImage = nil
        
        // Clear image cache
        croppedCache.removeAllObjects()
    }
    
    // MARK: - Task Management
    private func enqueueTask(_ block: @Sendable @escaping () -> Void) {
        let operation = BlockOperation { @Sendable in
            block()
        }
        activeOperations.insert(operation)
        
        operation.completionBlock = { [weak self, weak operation] in
            guard let operation = operation else { return }
            DispatchQueue.main.async {
                self?.activeOperations.remove(operation)
            }
        }
        
        taskQueue.addOperation(operation)
    }
    
    // MARK: - Lazy Initialization
    private let imageCompressionQuality: CGFloat = 0.8
    private lazy var fileManager: FileManager = .default

    private func saveImage(_ img: UIImage) throws -> URL {
        let fileName = UUID().uuidString + ".jpg"
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(fileName)
        
        // Save to memory cache
        cacheImage(img, withKey: fileName)
        
        // Save to disk cache for persistence
        CacheManager.shared.cacheImage(img, forKey: fileName)
        
        // Optimize image before saving
        let optimizedImage = img
            .withFixedOrientation()
            .compress(maxSize: 512 * 1024) ?? img
        
        // Save to disk
        try optimizedImage.jpegData(compressionQuality: imageCompressionQuality)?
            .write(to: url, options: .atomic)
        return url
    }
    
    private func loadImage(_ name: String) -> UIImage? {
        // Try memory cache first
        if let cached = getCachedImage(forKey: name) {
            return cached
        }
        
        // Try disk cache
        if let cached = CacheManager.shared.getImage(forKey: name) {
            // Add to memory cache
            cacheImage(cached, withKey: name)
            return cached
        }
        
        // Load from disk
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(name)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        
        // Cache for next time
        let optimized = image.optimized(quality: previewQuality)
        cacheImage(optimized, withKey: name)
        CacheManager.shared.cacheImage(optimized, forKey: name)
        
        return optimized
    }

    init() {
        TextScannerService.currentSystem = storedSystem    // مزامنة أوليّة
        setupQueue()
        
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        processingOperation?.cancel()
        processingTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor in
            AppStateManager.shared.cancelAllTasks()
        }
        croppedCache.removeAllObjects()
    }
}
