
import SwiftUI

/// Small floating panel that lets the user correct one digit while Live-OCR remains visible.
struct LiveFixPopover: View {
    @Binding var candidate: FixCandidate?
    @State private var text: String = ""

    var body: some View {
        if let cand = candidate {
            VStack(spacing: 12) {
                Text("Correct digit")
                    .font(.headline)

                Image(decorative: cand.image, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 60, height: 60)
                    .border(Color.primary.opacity(0.4))

                TextField("Digit", text: $text)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save") {
                        guard let n = Int(text) else { return }
                        SampleStore.save(image: cand.image, as: n)
                        candidate = nil        // dismiss
                        // (ScannerViewModel recalculates total later automatically)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") { candidate = nil }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .onAppear {                             // preload suggested digit
                if let sug = cand.suggested {
                    text = String(sug)
                }
            }
            .transition(.scale.combined(with: .opacity))
            .shadow(radius: 10)
        }
    }
}
