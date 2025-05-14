import SwiftUI
import AVFoundation

struct CroppedResultView: View {
    let image: UIImage
    let observations: [NumberObservation]

    private var sum: Double {
        observations.map(\.value).reduce(0, +)
    }

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

                    // Highlight rectangles
                    ForEach(observations) { obs in
                        let scale = fitted.width / image.size.width
                        Rectangle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: obs.rect.width  * scale,
                                   height: obs.rect.height * scale)
                            .position(
                                x: fitted.minX + (obs.rect.midX * scale),
                                y: fitted.minY + (obs.rect.midY * scale)
                            )
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
