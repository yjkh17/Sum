
import SwiftUI

/// Holds every sheet / full-screen-cover flag.
/// Knows nothing about OCR or numbers.
@MainActor
final class NavigationViewModel: ObservableObject {
    @Published var isShowingScanner      = false
    @Published var isShowingLiveScanner  = false
    @Published var isShowingPhotoPicker  = false
    @Published var isShowingCropper      = false
    @Published var isShowingResult       = false
}
