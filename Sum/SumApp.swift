import SwiftUI
import SwiftData

@main
struct SumApp: App {
    @StateObject private var modelManager = ModelManager.live
    @StateObject private var appState = AppStateManager.shared
    
    // Track app state
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Setup app services
        setupCrashReporting()
        setupAnalytics()
        setupLogging()
        
        // Start loading ML model in background
        DispatchQueue.global(qos: .userInitiated).async {
            DigitClassifierService.preloadModel()
        }
        
        // Configure global appearance
        configureAppearance()
    }
    
    private func configureAppearance() {
        // Configure navigation bar
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        
        // Configure toolbars
        let toolbarAppearance = UIToolbarAppearance()
        toolbarAppearance.configureWithDefaultBackground()
        UIToolbar.appearance().standardAppearance = toolbarAppearance
        UIToolbar.appearance().compactAppearance = toolbarAppearance
        UIToolbar.appearance().scrollEdgeAppearance = toolbarAppearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelManager.container)
                .environmentObject(appState)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        activateApp()
                    case .inactive:
                        deactivateApp()
                    case .background:
                        handleBackgroundTransition()
                    @unknown default:
                        break
                    }
                }
        }
    }
    
    private func activateApp() {
        Task { @MainActor in
            modelManager.refreshIfNeeded()
            appState.restoreState()
        }
    }
    
    private func deactivateApp() {
        Task { @MainActor in
            modelManager.saveChanges()
            appState.saveState()
        }
    }
    
    private func handleBackgroundTransition() {
        Task { @MainActor in
            modelManager.saveChanges()
            appState.saveState()
        }
        DigitClassifierService.cleanupIfNeeded()
    }
}

// MARK: - App Configuration
extension SumApp {
    private func setupCrashReporting() {
        #if DEBUG
        // Debug mode crash reporting
        print("[Crash Reporting] Initialized in debug mode")
        #else
        // Add production crash reporting here
        // Example: Firebase.configure()
        print("[Crash Reporting] Initialized in release mode")
        #endif
    }
    
    private func setupAnalytics() {
        #if DEBUG
        // Debug analytics
        print("[Analytics] Initialized in debug mode")
        #else
        // Add production analytics here
        // Example: Analytics.configure()
        print("[Analytics] Initialized in release mode")
        #endif
    }
    
    private func setupLogging() {
        #if DEBUG
        // Debug logging
        print("[Logging] Initialized in debug mode")
        #else
        // Add production logging here
        // Example: Logger.configure()
        print("[Logging] Initialized in release mode")
        #endif
    }
}

// MARK: - Optimized Model Container
@MainActor
private class ModelManager: ObservableObject {
    static let live = ModelManager()
    
    @Published private(set) var container: SwiftData.ModelContainer
    private var lastRefresh: Date?
    private let staleThreshold: TimeInterval = 300 // 5 minutes
    
    private init() {
        let schema = Schema([ScanRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            container = try SwiftData.ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    func refreshIfNeeded() {
        guard let last = lastRefresh,
              Date().timeIntervalSince(last) > staleThreshold else {
            return
        }
        // Reload data if stale
        lastRefresh = Date()
        
        #if DEBUG
        print("[ModelManager] Refreshing stale data")
        #endif
    }
    
    func saveChanges() {
        Task { @MainActor in
            do {
                try container.mainContext.save()
                #if DEBUG
                print("[ModelManager] Changes saved successfully")
                #endif
            } catch {
                print("[ModelManager] Failed to save context:", error)
            }
        }
    }
}
