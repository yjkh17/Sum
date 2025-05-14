
import SwiftUI

/// Draws coloured rectangles for every recognised number (unit-space 0…1 → view-space)
struct LiveHighlightOverlay: View {
    let rects: [CGRect]

    var body: some View {
        GeometryReader { geo in
            ForEach(rects.indices, id: \.self) { idx in
                let r = rects[idx]
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
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
