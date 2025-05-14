
import SwiftUI

/// Semi-transparent layer for drawing/clearing a crop rectangle over live camera feed.
struct LiveCropOverlay: View {
    @Binding var crop: CGRect?              // 0…1 unit space
    @State private var draft: CGRect? = nil
    @State private var start: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dim the area outside the crop
                if let r = crop {
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .mask(
                            Rectangle().path(in: geo.frame(in: .local))
                                .subtracting(Rectangle().path(in: rectInView(r, geo)))
                        )
                }

                // Draw live border (either active crop or current drag draft)
                if let r = crop ?? draft {
                    Rectangle()
                        .path(in: rectInView(r, geo))
                        .stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())   // allow gesture everywhere
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if start == nil { start = value.startLocation }
                        let s = start ?? value.startLocation
                        draft = CGRect(x: min(s.x, value.location.x),
                                       y: min(s.y, value.location.y),
                                       width: abs(value.location.x - s.x),
                                       height: abs(value.location.y - s.y))
                    }
                    .onEnded { _ in
                        if let d = draft {
                            crop = rectToUnit(d, geo)
                        }
                        draft = nil
                        start = nil
                    }
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Helpers
    private func rectInView(_ r: CGRect, _ geo: GeometryProxy) -> CGRect {
        CGRect(x: r.minX * geo.size.width,
               y: r.minY * geo.size.height,
               width: r.width  * geo.size.width,
               height: r.height * geo.size.height)
    }
    private func rectToUnit(_ r: CGRect, _ geo: GeometryProxy) -> CGRect {
        CGRect(x: r.minX / geo.size.width,
               y: r.minY / geo.size.height,
               width: r.width  / geo.size.width,
               height:r.height / geo.size.height)
    }
}
