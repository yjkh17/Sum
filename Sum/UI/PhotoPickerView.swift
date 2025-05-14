
import SwiftUI
import PhotosUI

/// Presents PHPicker, extracts numbers from the chosen photo, then returns them.
struct PhotoPickerView: UIViewControllerRepresentable {
    var onImageScanned: @MainActor ([Double]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter          = .images
        config.selectionLimit  = 1
        let picker             = PHPickerViewController(configuration: config)
        picker.delegate        = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        init(parent: PhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                Task { @MainActor in parent.onImageScanned([]) }
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let self,
                      let uiImage = object as? UIImage,
                      let cgImage = uiImage.cgImage else {
                    Task { @MainActor in self?.parent.onImageScanned([]) }
                    return
                }

                Task.detached {
                    let nums = (try? await TextScannerService.recognizeNumbers(in: cgImage)) ?? []
                    await MainActor.run {
                        self.parent.onImageScanned(nums)
                    }
                }
            }
        }
    }
}
