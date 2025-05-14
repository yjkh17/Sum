import SwiftUI
import PhotosUI

/// Presents the system photo-picker and returns one upright, downsized UIImage.
struct PhotoPickerView: View {
    var onImagePicked: @MainActor (UIImage) -> Void          // callback
    @Environment(\.dismiss) private var dismiss              // to close sheet

    @State private var pickerItem: PhotosPickerItem? = nil   // selection

    var body: some View {
        VStack {
            PhotosPicker(selection: $pickerItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                Label("Choose photo", systemImage: "photo.on.rectangle")
                    .font(.title3)
            }
            .accessibilityLabel("Choose photo from library")
        }
        // when the binding changes, load the image
        .onChange(of: pickerItem) { _, _ in
            loadImage()
        }
        .padding()
    }

    // MARK: - Load the selected photo
    private func loadImage() {
        guard let item = pickerItem else { return }
        Task {
            // 1) NSData → UIImage
            guard let data   = try? await item.loadTransferable(type: Data.self),
                  var uiImg  = UIImage(data: data)?.fixedOrientation()
            else { return }

            // 2) Down-scale very large images to ~1280px
            if let thumb = uiImg.preparingThumbnail(of: CGSize(width: 1280, height: 1280)) {
                uiImg = thumb
            }

            // 3) Return to caller on main-actor
            await MainActor.run {
                onImagePicked(uiImg)
                dismiss()
            }
        }
    }
}
