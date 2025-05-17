import SwiftUI

/// Holds every sheet / full-screen-cover flag and manages navigation state.
@MainActor
final class NavigationViewModel: ObservableObject {
    @Published var isShowingScanner      = false
    @Published var isShowingLiveScanner  = false
    @Published var isShowingPhotoPicker  = false
    @Published var isShowingCropper      = false
    @Published var isShowingResult       = false
    
    @AppStorage("lastView") private var lastView: String?
    
    // Navigation stack history
    private var navigationHistory: [String] = []
    private let maxHistoryItems = 10
    
    func pushView(_ identifier: String) {
        navigationHistory.append(identifier)
        if navigationHistory.count > maxHistoryItems {
            navigationHistory.removeFirst()
        }
        lastView = identifier
    }
    
    func popToRoot() {
        isShowingScanner = false
        isShowingLiveScanner = false
        isShowingPhotoPicker = false
        isShowingCropper = false
        isShowingResult = false
        navigationHistory.removeAll()
    }
    
    func restoreLastState() {
        guard let last = lastView else { return }
        switch last {
        case "scanner": isShowingScanner = true
        case "live": isShowingLiveScanner = true
        case "picker": isShowingPhotoPicker = true
        case "cropper": isShowingCropper = true
        case "result": isShowingResult = true
        default: break
        }
    }
}

// MARK: - Navigation State
extension NavigationViewModel {
    func dismissAll() {
        withAnimation {
            popToRoot()
        }
    }
    
    func handleMemoryWarning() {
        // If we're showing multiple screens, go back to root
        if navigationHistory.count > 1 {
            dismissAll()
        }
    }
}
