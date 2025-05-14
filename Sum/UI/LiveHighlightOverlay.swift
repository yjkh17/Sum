import SwiftUI

/// Draws coloured rectangles for every recognised number (unit-space 0…1 → view-space)
struct LiveHighlightOverlay: View {
    let rects     : [CGRect]
    let rectConfs : [Float]

    var body: some View {
        GeometryReader { geo in
            ForEach(rects.indices, id: \.self) { idx in
                let r = rects[idx]
                let conf  = idx < rectConfs.count ? rectConfs[idx] : 1
                let color : Color = conf < 0.30 ? .red
                                   : conf < 0.60 ? .orange : .green

                Rectangle()
                    .stroke(color, lineWidth: 2)
                    .frame(width:  r.width  * geo.size.width,
                           height: r.height * geo.size.height)
                    .position(x: r.midX * geo.size.width,
                              y: r.midY * geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
