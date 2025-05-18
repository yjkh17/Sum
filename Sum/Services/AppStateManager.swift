import Foundation
import SwiftUI
import Combine
import OSLog
import UIKit

@MainActor
final class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    // MARK: - App State
    @AppStorage("lastActiveTab") private var lastActiveTab: Int = 0
    @AppStorage("lastScanDate") private var lastScanDate: Date = .distantPast
    
    // MARK: - Background Tasks
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // MARK: - Performance Monitoring
    private var memoryWarningCount = 0
    private var lastMemoryWarning: Date?
    private let memoryWarningThreshold = 3  // Number of warnings before aggressive cleanup
    private let memoryWarningInterval: TimeInterval = 60  // Reset count after 1 minute
    
    enum ProcessingPriority {
        case low, normal, high
        
        var qos: QualityOfService {
            switch self {
            case .low: return .utility
            case .normal: return .userInitiated
            case .high: return .userInteractive
            }
        }
        
        static let allCases: [ProcessingPriority] = [.low, .normal, .high]
    }
    
    enum AppError: Error {
        case processingFailed(String)
        case resourceUnavailable(String)
        case taskCancelled
        
        var localizedDescription: String {
            switch self {
            case .processingFailed(let reason):
                return "Processing failed: \(reason)"
            case .resourceUnavailable(let resource):
                return "Resource unavailable: \(resource)"
            case .taskCancelled:
                return "Task was cancelled"
            }
        }
    }
    
    private var processingQueues: [ProcessingPriority: OperationQueue] = [:]
    private var activeOperations: Set<Operation> = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupQueues()
        setupNotifications()
    }
    
    private func setupQueues() {
        ProcessingPriority.allCases.forEach { priority in
            let queue = OperationQueue()
            queue.qualityOfService = priority.qos
            queue.maxConcurrentOperationCount = priority == .high ? 1 : 2
            processingQueues[priority] = queue
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleBackgroundTransition()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Task Management
    func beginBackgroundTask() {
        endBackgroundTask() // End any existing task
        
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    func enqueueTask(_ priority: ProcessingPriority = .normal, 
                     operation: @Sendable @escaping () -> Void) {
        let op = BlockOperation(block: operation)
        activeOperations.insert(op)
        
        op.completionBlock = { [weak self, weak op] in
            guard let op = op else { return }
            DispatchQueue.main.async {
                self?.activeOperations.remove(op)
            }
        }
        
        processingQueues[priority]?.addOperation(op)
    }
    
    func cancelAllTasks() {
        processingQueues.values.forEach { $0.cancelAllOperations() }
        activeOperations.removeAll()
        endBackgroundTask()
    }
    
    // MARK: - State Management
    func saveState() {
        lastScanDate = Date()
    }
    
    func restoreState() {
        // Restore any saved state when app becomes active
    }
    
    // MARK: - Memory Management
    private func handleMemoryWarning() {
        if let last = lastMemoryWarning,
           Date().timeIntervalSince(last) > memoryWarningInterval {
            memoryWarningCount = 0
        }
        
        memoryWarningCount += 1
        lastMemoryWarning = Date()
        
        if memoryWarningCount >= memoryWarningThreshold {
            performAggressiveCleanup()
        } else {
            performLightCleanup()
        }
    }
    
    private func handleBackgroundTransition() {
        saveState()
        performLightCleanup()
    }
    
    private func performLightCleanup() {
        DigitClassifierService.cleanupIfNeeded()
    }
    
    private func performAggressiveCleanup() {
        performLightCleanup()
        URLCache.shared.removeAllCachedResponses()
        cancelAllTasks()
        memoryWarningCount = 0
    }
    
    private func log(_ message: String) {
        #if DEBUG
        print("[Sum] \(message)")
        #else
        os_log("%{public}@", type: .default, message)
        #endif
    }
    
    func handleError(_ error: Error) {
        if let appError = error as? AppError {
            log(appError.localizedDescription)
        } else {
            log("Unexpected error: \(error.localizedDescription)")
        }
    }
}
