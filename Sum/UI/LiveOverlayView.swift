import SwiftUI
import Darwin

/// A translucent overlay that shows the live total while scanning.
struct LiveOverlayView: View {
    let numbers: [Double]
    @State private var previousTotal: Double = 0
    @State private var perspectivePhase: Double = 0
    @State private var extraPerspective: Double = 0
    @State private var isAppearing = false
    
    // Cache the total
    private var total: Double {
        numbers.reduce(0, +)
    }
    
    private var didIncrease: Bool {
        total > previousTotal
    }
    
    // Use equatable to prevent unnecessary updates
    private var shouldShowChange: Bool {
        abs(total - previousTotal) > 0.001
    }
    
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                // Change indicator
                if shouldShowChange {
                    Image(systemName: didIncrease ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(didIncrease ? .green : .red)
                        .symbolEffect(.bounce, value: total)
                }
                
                // Total
                HStack(spacing: 4) {
                    Text("Total:")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Text(total, format: .number)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10)
            )
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            }
            // Add subtle perspective movement
            .rotation3DEffect(
                .degrees(sin(perspectivePhase) * 2 + extraPerspective),
                axis: (x: 1, y: 0, z: 0)
            )
            .rotation3DEffect(
                .degrees(cos(perspectivePhase) * 2 + extraPerspective),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 32)
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 20)
        .animation(.smooth, value: total)
        .onChange(of: total) { _, newValue in
            withAnimation {
                previousTotal = newValue
                // Add extra bounce to perspective
                extraPerspective = didIncrease ? 5 : -5
            }
            // Reset extra perspective after bounce
            withAnimation(.spring(dampingFraction: 0.6).delay(0.1)) {
                extraPerspective = 0
            }
        }
        .onAppear {
            // Start perspective animation
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                perspectivePhase = .pi * 2
            }
            
            // Fade in
            withAnimation(.easeOut(duration: 0.3)) {
                isAppearing = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        LiveOverlayView(numbers: [42.5, 13.75, 99.99])
    }
}
