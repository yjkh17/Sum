import SwiftUI

/// Holds every sheet / full-screen-cover flag and manages navigation state.
@MainActor
final class NavigationViewModel: ObservableObject {
    @Published var isShowingScanner      = false
    @Published var isShowingLiveScanner  = false
    @Published var isShowingPhotoPicker  = false
    @Published var isShowingCropper      = false
    @Published var isShowingResult       = false
    
    /// Dismiss all currently presented screens.
    func dismissAll() {
        isShowingScanner = false
        isShowingLiveScanner = false
        isShowingPhotoPicker = false
        isShowingCropper = false
        isShowingResult = false
    }
}

