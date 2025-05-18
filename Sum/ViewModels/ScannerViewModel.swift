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
    
    private static let croppedCache = NSCache<NSString, UIImage>()
    
    private static let cacheConfig: Void = {
        ScannerViewModel.croppedCache.totalCostLimit = 50 * 1024 * 1024  // 50MB limit
        ScannerViewModel.croppedCache.countLimit = 100 // Max 100 items
    }()

    private func cacheImage(_ image: UIImage, withKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4)  // Approx bytes
        Self.croppedCache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    private func getCachedImage(forKey key: String) -> UIImage? {
        return Self.croppedCache.object(forKey: key as NSString)
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
            photoNumbers = nums
            updateProgress(0.3)
            
            if !fixes.isEmpty {
                let fixImages = fixes.map { (UIImage(cgImage: $0.image), UUID().uuidString) }
                processBatchImages(fixImages)
                
                _pendingFixes = fixes
                if !isShowingFixSheet {
                    isShowingFixSheet = true
                }
            }
            updateProgress(0.7)
            recalcTotals()
            updateProgress(1.0)
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
        if let croppedImage = try? image.optimized(quality: previewQuality) {
            _croppedImage = croppedImage
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
    }

    @MainActor
    private func persistRecord(image: UIImage, in context: ModelContext) {
        let rec = ScanRecord()
        rec.total = sum
        rec.numbers = numbers
        
        // Save high quality version for archive
        if let archiveImage = try? image.optimized(quality: archiveQuality),
           let url = try? saveImage(archiveImage) {
            rec.imagePath = url.lastPathComponent
        }
        
        context.insert(rec)
    }

    private func saveImage(_ img: UIImage) throws -> URL {
        let fileName = UUID().uuidString + ".jpg"
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(fileName)
        
        // Save to memory cache
        cacheImage(img, withKey: fileName)
        
        // Save to disk cache for persistence
        CacheManager.shared.cacheImage(img, forKey: fileName)
        
        // Optimize image before saving
        let optimizedImage = (try? img
            .withFixedOrientation()
            .optimized(quality: .medium)) ?? img
        
        // Save to disk
        guard let data = optimizedImage.jpegData(compressionQuality: imageCompressionQuality) else {
            throw AppStateManager.AppError.processingFailed("Failed to create JPEG data")
        }
        try data.write(to: url, options: .atomicWrite)
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
        if let optimized = try? image.optimized(quality: previewQuality) {
            cacheImage(optimized, withKey: name)
            CacheManager.shared.cacheImage(optimized, forKey: name)
            return optimized
        }
        return image
    }

    /// Recompute totals when any source updates
    private func recalcTotals() {
        numbers = capturedNumbers + photoNumbers
        sum = numbers.reduce(0, +)
        lastSum = sum
        showSumAlert = true
    }

    // MARK: - Helpers
    private func resetNumbers() {
        capturedNumbers = []
        photoNumbers = []
        liveNumbers.reserveCapacity(10)
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

    func handleLiveNumbersUpdate(_ numbers: [Double]) {
        autoreleasepool {
            liveNumbers = numbers
            liveSum = numbers.reduce(0, +)
        }
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
                
                let optimizedImage = try image.optimized(quality: .medium)
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
                                let _ = try await self.processOptimizedImage(optimizedImage)
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
    private func processOptimizedImage(_ image: UIImage) async throws -> UIImage {
        guard !Task.isCancelled else {
            throw AppStateManager.AppError.taskCancelled
        }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            let operation = BlockOperation { @Sendable in
                autoreleasepool {
                    do {
                        if image.size.width < 1 || image.size.height < 1 {
                            continuation.resume(throwing: AppStateManager.AppError.processingFailed("Invalid image dimensions"))
                            return
                        }
                        
                        // Process image in autorelease pool to manage memory
                        let optimized = try image.optimized(quality: .medium)
                        continuation.resume(returning: optimized)
                        
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
        let processedCount = Atomic(0)
        
        let chunkSize = max(5, images.count / 4) // Adaptive chunk size
        let chunks = stride(from: 0, through: images.count - 1, by: chunkSize).map {
            Array(images[($0)..<min($0 + chunkSize, images.count)])
        }
        
        for chunk in chunks {
            autoreleasepool {
                let operations = chunk.map { (image, id) in
                    CacheManager.BatchOperation(
                        key: id,
                        image: image,
                        quality: .medium
                    ) { [weak self] optimized in
                        guard let self = self else { return }
                        
                        let current = processedCount.increment()
                        
                        Task { @MainActor in
                            self.updateProgress(Double(current) / totalCount)
                            
                            if let optimized = optimized {
                                self.updateProcessedImage(optimized, forId: id)
                            }
                            
                            if current == images.count {
                                self.processingState = .idle
                                self.finishProcessing()
                            }
                        }
                    }
                }
                CacheManager.shared.processBatchOperations(operations)
            }
        }
        AppStateManager.shared.beginBackgroundTask()
    }
    
    private func updateProcessedImage(_ image: UIImage, forId id: String) {
        autoreleasepool {
            if let croppedImage = try? image.optimized(quality: .medium) {
                _croppedImage = croppedImage
            }
            
            withAnimation {
                isShowingResult = true
            }
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
        Self.croppedCache.removeAllObjects()
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

    private final class Atomic<T: Numeric> {
        private let lock = NSLock()
        private var value: T
        
        init(_ value: T) {
            self.value = value
        }
        
        func increment() -> T {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
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
            Self.croppedCache.removeAllObjects()
        }
    }
}
