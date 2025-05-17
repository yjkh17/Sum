import Foundation
import SwiftUI
import Combine

@MainActor
final class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    // MARK: - App State
    @AppStorage("lastActiveTab") private var lastActiveTab: Int = 0
    @AppStorage("lastScanDate") private var lastScanDate: Date = .distantPast
    
    // MARK: - Performance Monitoring
    private var memoryWarningCount = 0
    private var lastMemoryWarning: Date?
    private let memoryWarningThreshold = 3  // Number of warnings before aggressive cleanup
    private let memoryWarningInterval: TimeInterval = 60  // Reset count after 1 minute
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Subscribe to memory warnings
        NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
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
        // Reset count if last warning was too long ago
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
    
    private func performLightCleanup() {
        // Release non-essential resources
        DigitClassifierService.cleanupIfNeeded()
    }
    
    private func performAggressiveCleanup() {
        // More aggressive cleanup when under memory pressure
        performLightCleanup()
        
        // Clear image caches
        URLCache.shared.removeAllCachedResponses()
        
        // Reset warning count
        memoryWarningCount = 0
    }
}