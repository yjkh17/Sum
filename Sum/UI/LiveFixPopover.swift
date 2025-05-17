import SwiftUI

/// Small floating panel that lets the user correct one digit while Live-OCR remains visible.
struct LiveFixPopover: View {
    @Binding var candidate: FixCandidate?
    @State private var text: String = ""
    @EnvironmentObject private var scanVM: ScannerViewModel
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        if let cand = candidate {
            VStack(spacing: 12) {
                Text("Correct digit")
                    .font(.headline)

                Image(decorative: cand.image, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 60, height: 60)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )

                TextField("Digit", text: $text)
                    .focused($isTextFieldFocused)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveCorrection() }

                HStack(spacing: 16) {
                    Button("Save") { saveCorrection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.isEmpty)

                    Button("Cancel") { 
                        isTextFieldFocused = false
                        candidate = nil 
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(
                .regularMaterial.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .onAppear {
                if let sug = cand.suggested {
                    text = String(sug)
                }
                isTextFieldFocused = true
            }
            .transition(.scale.combined(with: .opacity))
            .shadow(radius: 12, y: 4)
        }
    }
    
    private func saveCorrection() {
        guard let n = Int(text),
              let cand = candidate else { return }
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Save sample and update
        SampleStore.save(image: cand.image, as: n)
        scanVM.applyLiveCorrection(
            old: cand.suggested.map { Double($0) },
            new: Double(n)
        )
        
        // Dismiss
        isTextFieldFocused = false
        candidate = nil
    }
}
