import SwiftUI

struct ProcessingOverlay: View {
    let progress: Double
    let isVisible: Bool
    
    var body: some View {
        Group {
            if isVisible {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 16) {
                        ProgressView(value: progress) {
                            Text("Processing...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .progressViewStyle(.circular)
                        .tint(.white)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: isVisible)
    }
}