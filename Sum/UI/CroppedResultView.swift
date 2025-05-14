

import SwiftUI

struct CroppedResultView: View {
    let image: UIImage
    let observations: [NumberObservation]

    private var sum: Double {
        observations.map(\.value).reduce(0, +)
    }

    var body: some View {
        VStack {
            GeometryReader { geo in
                let scale = min(geo.size.width / image.size.width,
                                geo.size.height / image.size.height)
                let imgW  = image.size.width * scale
                let imgH  = image.size.height * scale
                let offsetX = (geo.size.width  - imgW) / 2
                let offsetY = (geo.size.height - imgH) / 2

                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()

                    ForEach(observations) { obs in
                        Rectangle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: obs.rect.width  * scale,
                                   height: obs.rect.height * scale)
                            .offset(x: obs.rect.minX * scale + offsetX,
                                    y: obs.rect.minY * scale + offsetY)
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.85))
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

