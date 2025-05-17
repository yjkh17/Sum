import SwiftUI

struct FixDigitSheet: View {
    @Binding var fixes: [FixCandidate]          // live queue
    var onFinish: () -> Void                    // callback when queue empty

    @State private var input = ""
    @FocusState private var isInputFocused: Bool
    @State private var isImageLoaded = false
    
    private var confidenceColor: Color {
        guard let confidence = fixes.first?.confidence else { return .gray }
        switch confidence {
        case ..<0.3: return .red
        case 0.3..<0.6: return .orange
        default: return .green
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let first = fixes.first {
                    VStack(spacing: 20) {
                        // MARK: - Image Preview
                        Image(uiImage: UIImage(cgImage: first.image))
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 8)
                            .opacity(isImageLoaded ? 1 : 0)
                            .scaleEffect(isImageLoaded ? 1 : 0.8)
                            .onAppear { animateImage() }

                        // MARK: - Info Section
                        VStack(spacing: 8) {
                            Text("Confidence")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            Text("\(Int(first.confidence * 100))%")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(confidenceColor)
                            
                            Text("\(fixes.count) more to check")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .opacity(isImageLoaded ? 1 : 0)
                        .offset(y: isImageLoaded ? 0 : 20)

                        // MARK: - Input Section
                        VStack(spacing: 16) {
                            TextField("Correct digit", text: $input)
                                .focused($isInputFocused)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.title3)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .onSubmit(saveCurrentFix)

                            HStack(spacing: 20) {
                                Button(role: .cancel) {
                                    fixes.removeFirst()
                                    if fixes.isEmpty { onFinish() }
                                } label: {
                                    Text("Skip")
                                        .frame(width: 100)
                                }
                                .buttonStyle(.bordered)

                                Button(action: saveCurrentFix) {
                                    Text("Save")
                                        .frame(width: 100)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(input.isEmpty)
                            }
                        }
                        .opacity(isImageLoaded ? 1 : 0)
                        .offset(y: isImageLoaded ? 0 : 20)
                    }
                    .padding()
                    .animation(.spring(dampingFraction: 0.7), value: isImageLoaded)
                } else {
                    ProgressView()
                }
            }
            .padding()
            .navigationTitle("Fix Digit")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { isInputFocused = true }
        }
    }
    
    private func animateImage() {
        withAnimation(.spring(dampingFraction: 0.7)) {
            isImageLoaded = true
        }
    }
    
    private func saveCurrentFix() {
        guard let val = Int(input),
              let firstFix = fixes.first
        else { return }
        
        // Save and give feedback
        SampleStore.save(image: firstFix.image, as: val)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Reset and update queue
        isImageLoaded = false
        fixes.removeFirst()
        input = ""
        
        // Finish if done
        if fixes.isEmpty {
            onFinish()
        } else {
            // Animate next image
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                animateImage()
            }
        }
    }
}
