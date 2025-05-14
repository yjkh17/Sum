import SwiftUI
import AVFoundation

struct CroppedResultView: View {
    let image: UIImage
    let observations: [NumberObservation]

    private var sum: Double { observations.map(\.value).reduce(0, +) }

    /// Formatter for both per-item labels and total
    private static let formatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        return nf
    }()

    var body: some View {
        VStack {
            GeometryReader { geo in
                // Let AVMakeRect calculate the fitted frame
                let fitted = AVMakeRect(aspectRatio: image.size,
                                        insideRect: geo.frame(in: .local))

                ZStack(alignment: .topLeading) {
                    // The photo
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)

                    // Highlight rectangles + value labels
                    ForEach(observations) { obs in
                        let scale  = fitted.width / image.size.width
                        let rectW  = obs.rect.width  * scale
                        let rectH  = obs.rect.height * scale
                        let posX   = fitted.minX + obs.rect.midX * scale
                        let posY   = fitted.minY + obs.rect.midY * scale

                        // 1) Yellow rectangle
                        Rectangle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: rectW, height: rectH)
                            .position(x: posX, y: posY)

                        // 2) Numeric label just below the rectangle
                        if let str = Self.formatter.string(from: obs.value as NSNumber) {
                            Text(str)
                                .font(.caption.bold())
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 4)
                                .background(
                                    Color.black.opacity(0.7)
                                        .cornerRadius(4)
                                )
                                .position(x: posX, y: posY + rectH/2 + 12)
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            Text("Total: \(sum, format: .number)")
                .font(.largeTitle.bold())
                .padding()

            Spacer()
        }
        .foregroundStyle(.white)
        .background(Color.black)
    }
}
