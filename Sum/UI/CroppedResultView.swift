import SwiftUI
import AVFoundation

struct CroppedResultView: View {
    let image: UIImage
    let observations: [NumberObservation]
    @State private var isAnimating = false
    @State private var selectedObservation: NumberObservation?

    private var sum: Double { observations.map(\.value).reduce(0, +) }

    /// Formatter for both per-item labels and total
    private static let formatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        return nf
    }()
    
    private func colorFor(confidence: Float) -> Color {
        switch confidence {
        case ..<0.30: return .red
        case 0.30..<0.60: return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                // Let AVMakeRect calculate the fitted frame
                let fitted = AVMakeRect(aspectRatio: image.size,
                                      insideRect: geo.frame(in: .local))

                ZStack(alignment: .topLeading) {
                    // The photo with fade-in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)
                        .opacity(isAnimating ? 1 : 0)

                    // Highlight rectangles + value labels
                    ForEach(observations) { obs in
                        let scale  = fitted.width / image.size.width
                        let rectW  = obs.rect.width  * scale
                        let rectH  = obs.rect.height * scale
                        let posX   = fitted.minX + obs.rect.midX * scale
                        let posY   = fitted.minY + obs.rect.midY * scale
                        let isSelected = selectedObservation?.id == obs.id
                        let color = colorFor(confidence: obs.confidence)

                        // Highlight rectangle
                        Rectangle()
                            .stroke(color, lineWidth: isSelected ? 3 : 2)
                            .background(color.opacity(0.1))
                            .frame(width: rectW, height: rectH)
                            .position(x: posX, y: posY)
                            .scaleEffect(isSelected ? 1.1 : 1.0)
                            .opacity(isAnimating ? 1 : 0)
                            .animation(.easeInOut.delay(Double(observations.firstIndex(of: obs) ?? 0) * 0.1),
                                     value: isAnimating)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    selectedObservation = selectedObservation?.id == obs.id ? nil : obs
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }

                        // Value label
                        if let str = Self.formatter.string(from: obs.value as NSNumber) {
                            Text(str)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.black.opacity(0.7))
                                        .shadow(radius: 3)
                                )
                                .position(x: posX, y: posY + rectH/2 + 12)
                                .opacity(isAnimating ? 1 : 0)
                                .offset(y: isAnimating ? 0 : 10)
                                .animation(.easeInOut.delay(Double(observations.firstIndex(of: obs) ?? 0) * 0.15),
                                         value: isAnimating)
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            // Total section
            VStack(spacing: 8) {
                Text("Total")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 10)
                
                Text(sum, format: .number)
                    .font(.system(size: 42, weight: .bold))
                    .contentTransition(.numericText())
                    .opacity(isAnimating ? 1 : 0)
                    .scaleEffect(isAnimating ? 1 : 0.8)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(isAnimating ? 1 : 0)
            )
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isAnimating = true
            }
        }
        .onTapGesture {
            withAnimation {
                selectedObservation = nil
            }
        }
    }
}
