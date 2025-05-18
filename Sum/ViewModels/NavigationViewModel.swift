import SwiftUI

/// Holds every sheet / full-screen-cover flag and manages navigation state.
@MainActor
final class NavigationViewModel: ObservableObject {
    enum Screen: String {
        case scanner, live, picker, cropper, result
    }

    @Published var isShowingScanner      = false
    @Published var isShowingLiveScanner  = false
    @Published var isShowingPhotoPicker  = false
    @Published var isShowingCropper      = false
    @Published var isShowingResult       = false

    @AppStorage("lastView") private var lastView: String?

    private var navigationHistory: [Screen] = []
    private let maxHistoryItems = 10

    // MARK: - Presentation Helpers
    func show(_ screen: Screen) {
        switch screen {
        case .scanner: isShowingScanner = true
        case .live:    isShowingLiveScanner = true
        case .picker:  isShowingPhotoPicker = true
        case .cropper: isShowingCropper = true
        case .result:  isShowingResult = true
        }
        push(screen)
    }

    func hideCurrent() {
        guard let last = navigationHistory.popLast() else { return }
        lastView = navigationHistory.last?.rawValue
        switch last {
        case .scanner: isShowingScanner = false
        case .live:    isShowingLiveScanner = false
        case .picker:  isShowingPhotoPicker = false
        case .cropper: isShowingCropper = false
        case .result:  isShowingResult = false
        }
    }

    /// Dismiss all currently presented screens.
    func dismissAll() {
        withAnimation { popToRoot() }
    }

    /// Restore the last viewed screen on launch.
    func restoreLastState() {
        guard let raw = lastView, let screen = Screen(rawValue: raw) else { return }
        show(screen)
    }

    // MARK: - Private Helpers
    private func push(_ screen: Screen) {
        navigationHistory.append(screen)
        if navigationHistory.count > maxHistoryItems {
            navigationHistory.removeFirst()
        }
        lastView = screen.rawValue
    }

    private func popToRoot() {
        isShowingScanner = false
        isShowingLiveScanner = false
        isShowingPhotoPicker = false
        isShowingCropper = false
        isShowingResult = false
        navigationHistory.removeAll()
        lastView = nil
    }
}

