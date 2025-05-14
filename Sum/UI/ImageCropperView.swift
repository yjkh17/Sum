import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    var onCropFinished: @MainActor (UIImage, [NumberObservation]) -> Void
    @Environment(\.dismiss) private var dismiss

    // MARK: - Selection state
    /// Finalised selection (0‥1). Nil until user draws first rectangle
    @State private var rect: CGRect? = nil
    /// Live rectangle being drawn
    @State private var draftRect: CGRect? = nil
    /// Drag start in view-space
    @State private var dragStart: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in               // geo gives container size
            ScrollView([.vertical, .horizontal]) {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                    // selection overlay
                    Rectangle()
                        .path(in: selectionRect(in: geo.size))
                        .stroke(Color.yellow, lineWidth: 3)
                        .background(
                            Rectangle()
                                .fill(Color.black.opacity(0.25))
                                .mask(Rectangle().path(in: selectionRect(in: geo.size)))
                        )
                    // MARK: Draw-new-rectangle gesture
                    .contentShape(Rectangle())        // capture taps outside current rect
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStart == nil {           // drag began
                                    dragStart = value.startLocation
                                }
                                // live draft rect in view-coords
                                let start = dragStart ?? value.startLocation
                                draftRect = CGRect(
                                    x: min(start.x, value.location.x),
                                    y: min(start.y, value.location.y),
                                    width: abs(value.location.x - start.x),
                                    height: abs(value.location.y - start.y)
                                )
                            }
                            .onEnded { _ in
                                guard let draft = draftRect else { return }
                                // convert to 0‥1 image-space
                                let size = geo.size
                                let imgWidth  = CGFloat(image.size.width)
                                let imgHeight = CGFloat(image.size.height)
                                let viewWidth = size.width
                                let viewHeight = max(image.size.height * size.width / image.size.width, size.height)
                                let x = draft.minX / viewWidth
                                let y = draft.minY / viewHeight
                                let width = draft.width / viewWidth
                                let height = draft.height / viewHeight
                                rect = CGRect(x: x, y: y, width: width, height: height).normalized()

                                // Reset temp states
                                dragStart = nil
                                draftRect = nil
                            }
                    )
                }
                // Size equals the actual rendered image inside geo
                .frame(width: geo.size.width,
                       height: max(image.size.height * geo.size.width / image.size.width,
                                   geo.size.height))
                // centre inside the scroll view
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .center)
            }
            .toolbar {
                // DONE —— runs crop + OCR
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        cropAndScan(size: geo.size)
                    }
                    .disabled(rect == nil)          // inactive until a rectangle exists
                }
                
                // CANCEL —— simply close the cropper
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // We now receive `geo.size` each time; compute selection live:
    private func selectionRect(in size: CGSize) -> CGRect {
        guard let r = rect ?? draftRect else { return .zero }
        if rect == nil { return r }                       // draft is in view-space
        // committed rect is normalised, convert to view-space
        let imgWidth  = CGFloat(image.size.width)
        let imgHeight = CGFloat(image.size.height)
        let viewWidth = size.width
        let viewHeight = max(image.size.height * size.width / image.size.width, size.height)
        return CGRect(x: r.minX * viewWidth,
                      y: r.minY * viewHeight,
                      width: r.width * viewWidth,
                      height: r.height * viewHeight)
    }

    private func cropAndScan(size: CGSize) {
        guard let selection = rect,                     // ensure we have rect
              let cgImage = image.cgImage else { return }
        let imgWidth  = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)

        // convert rect (0…1) → pixel space
        let crop = CGRect(x: selection.minX * imgWidth,
                          y: selection.minY * imgHeight,
                          width: selection.width * imgWidth,
                          height: selection.height * imgHeight)
            .integral

        guard let cropped = cgImage.cropping(to: crop) else { return }

        Task.detached {
            let obs   = (try? await TextScannerService.recognizeNumberObservations(in: cropped)) ?? []
            let cropImage = UIImage(cgImage: cropped)
            await MainActor.run {
                onCropFinished(cropImage, obs)
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

fileprivate extension CGRect {
    /// ensure origin & size are within 0‥1
    func normalized() -> CGRect {
        var r = self
        r.origin.x.clamp(to: 0...1)
        r.origin.y.clamp(to: 0...1)
        r.size.width.clamp(to: 0...(1 - r.origin.x))
        r.size.height.clamp(to: 0...(1 - r.origin.y))
        return r
    }
}
