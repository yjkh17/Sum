import SwiftUI

/// Draw coloured rectangles for each recognised number.
/// `rects` are in unit-space (0…1); `rectConfs` hold matching confidences 0…1.
struct LiveHighlightOverlay: View {
    let rects: [CGRect]
    let rectConfs: [Float]
    var onTap: (Int) -> Void = { _ in }
    @State private var tappedIndex: Int? = nil
    @State private var shimmerOffset: CGFloat = -1
    
    var body: some View {
        GeometryReader { geo in
            ForEach(rects.indices, id: \.self) { index in
                HighlightView(
                    rect: rects[index],
                    confidence: index < rectConfs.count ? rectConfs[index] : 1,
                    index: index,
                    screenSize: geo.size,
                    shimmerOffset: shimmerOffset,
                    isSelected: index == tappedIndex
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        tappedIndex = index
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.2)) { 
                            tappedIndex = nil 
                        }
                    }
                    onTap(index)
                }
            }
        }
        .ignoresSafeArea()
        .drawingGroup() // Use Metal for rendering
        .animation(.easeOut(duration: 0.2), value: rects)
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 1
            }
        }
    }
}

// MARK: - Single Highlight View
private struct HighlightView: View {
    let rect: CGRect
    let confidence: Float
    let index: Int
    let screenSize: CGSize
    let shimmerOffset: CGFloat
    let isSelected: Bool
    let onTap: () -> Void
    
    // Cache expensive computations
    private let baseRect: CGRect
    private let color: Color
    
    init(rect: CGRect, confidence: Float, index: Int, screenSize: CGSize,
         shimmerOffset: CGFloat, isSelected: Bool, onTap: @escaping () -> Void) {
        self.rect = rect
        self.confidence = confidence
        self.index = index
        self.screenSize = screenSize
        self.shimmerOffset = shimmerOffset
        self.isSelected = isSelected
        self.onTap = onTap
        
        // Precalculate expensive values
        self.baseRect = CGRect(
            x: CGFloat(rect.minX) * screenSize.width,
            y: CGFloat(rect.minY) * screenSize.height,
            width: CGFloat(rect.width) * screenSize.width,
            height: CGFloat(rect.height) * screenSize.height
        )
        self.color = HighlightView.colorFor(confidence: confidence)
    }
    
    @State private var isRecognized = false
    @State private var perspectivePhase: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var stretchScale: CGSize = .init(width: 1, height: 1)
    @State private var extraPerspective: Double = 0
    
    // Make color calculation static to avoid recreating
    private static func colorFor(confidence: Float) -> Color {
        switch confidence {
        case ..<0.30: return .blue.opacity(0.3)
        case 0.30..<0.60: return .blue.opacity(0.2)
        default: return .white.opacity(0.4)
        }
    }
    
    private func makeConfidencePulse(_ baseRect: CGRect, in size: CGSize) -> some View {
        let pulseRect = baseRect.insetBy(dx: -2, dy: -2)
        return ZStack {
            // Base pulse
            perspectiveRect(baseRect: pulseRect, in: size)
                .stroke(color, lineWidth: 1)
                .scaleEffect(pulseScale)
                .opacity(2 - pulseScale)
            
            // Extra pulses with offset phases
            perspectiveRect(baseRect: pulseRect, in: size)
                .stroke(color, lineWidth: 0.5)
                .scaleEffect(pulseScale * 1.1)
                .opacity((2 - pulseScale) * 0.5)
            
            perspectiveRect(baseRect: pulseRect, in: size)
                .stroke(color, lineWidth: 0.5)
                .scaleEffect(pulseScale * 1.2)
                .opacity((2 - pulseScale) * 0.3)
        }
    }

    private func perspectiveRect(baseRect: CGRect, in size: CGSize) -> Path {
        // Calculate perspective distortion based on position
        let yRatio = baseRect.midY / size.height
        let xRatio = baseRect.midX / size.width
        
        // Add subtle movement to perspective
        let moveX = sin(perspectivePhase) * 0.01
        let moveY = cos(perspectivePhase) * 0.01
        
        // More distortion at edges, less in center
        let yPerspective = 0.1 * (yRatio - 0.5) + moveY + extraPerspective
        let xPerspective = 0.05 * (xRatio - 0.5) + moveX
        
        // Apply perspective to each corner
        let topLeft = CGPoint(
            x: baseRect.minX - xPerspective * baseRect.width,
            y: baseRect.minY - yPerspective * baseRect.height
        )
        let topRight = CGPoint(
            x: baseRect.maxX + xPerspective * baseRect.width,
            y: baseRect.minY - yPerspective * baseRect.height
        )
        let bottomRight = CGPoint(
            x: baseRect.maxX + xPerspective * baseRect.width,
            y: baseRect.maxY + yPerspective * baseRect.height
        )
        let bottomLeft = CGPoint(
            x: baseRect.minX - xPerspective * baseRect.width,
            y: baseRect.maxY + yPerspective * baseRect.height
        )
        
        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        return path
    }

    var body: some View {
        ZStack {
            // Main fill with inner shadow
            perspectiveRect(baseRect: baseRect, in: screenSize)
                .fill(color)
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            
            // Shimmer effect
            perspectiveRect(baseRect: baseRect, in: screenSize)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.2), location: 0.3),
                            .init(color: .white.opacity(0.2), location: 0.7),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: screenSize.width * shimmerOffset)
                .opacity(isSelected ? 0 : 1)
            
            // Recognition animation
            if !isRecognized {
                perspectiveRect(baseRect: baseRect, in: screenSize)
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(1.2)
                    .opacity(0)
                    .onAppear {
                        // Jelly effect on recognition
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                            stretchScale = .init(width: 1.1, height: 0.9)
                            extraPerspective = 0.05
                        }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.1)) {
                            stretchScale = .init(width: 0.95, height: 1.05)
                            extraPerspective = -0.03
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.2)) {
                            stretchScale = .init(width: 1, height: 1)
                            extraPerspective = 0
                        }
                        
                        withAnimation(.easeOut(duration: 0.5)) {
                            isRecognized = true
                        }
                    }
            }
            
            // Confidence pulse with perspective
            if isRecognized {
                makeConfidencePulse(baseRect, in: screenSize)
            }
        }
        .scaleEffect(stretchScale)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            perspectivePhase = .random(in: 0...(.pi * 2))
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                perspectivePhase += .pi * 2
            }
            
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.05
            }
        }
    }
}
