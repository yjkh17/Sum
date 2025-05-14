
import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    var onCropFinished: @MainActor ([Double]) -> Void
    @Environment(\.dismiss) private var dismiss

    // Selection frame in image-space (0…1)
    @State private var rect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.3)
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let imgSize = geo.size
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // selection overlay
                Rectangle()
                    .path(in: selectionRect(in: imgSize))
                    .stroke(Color.yellow, lineWidth: 3)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.25))
                            .mask(Rectangle().path(in: selectionRect(in: imgSize)))
                    )
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                let dx = value.translation.width  / imgSize.width
                                let dy = value.translation.height / imgSize.height
                                rect.origin.x += dx
                                rect.origin.y += dy
                                rect.origin.x.clamp(to: 0...1-rect.width)
                                rect.origin.y.clamp(to: 0...1-rect.height)
                            }
                    )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crop & Sum") { cropAndScan(size: imgSize) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func selectionRect(in size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width,
               y: rect.minY * size.height,
               width: rect.width  * size.width,
               height: rect.height * size.height)
    }

    private func cropAndScan(size: CGSize) {
        guard let cgImage = image.cgImage else { return }
        let imgWidth  = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)

        // convert rect (0…1) → pixel space
        let crop = CGRect(x: rect.minX * imgWidth,
                          y: rect.minY * imgHeight,
                          width: rect.width * imgWidth,
                          height: rect.height * imgHeight)
            .integral

        guard let cropped = cgImage.cropping(to: crop) else { return }

        Task.detached {
            let nums = (try? await TextScannerService.recognizeNumbers(in: cropped)) ?? []
            await MainActor.run {
                onCropFinished(nums)
                dismiss()
            }
        }
    }
}

fileprivate extension Comparable {
    mutating func clamp(to range: ClosedRange<Self>) {
        self = min(max(self, range.lowerBound), range.upperBound)
    }
}
