import SwiftUI

struct FixDigitSheet: View {
    @Binding var fixes: [FixCandidate]          // live queue
    var onFinish: () -> Void                    // callback when queue empty

    @State private var input = ""

    var body: some View {
        VStack(spacing: 24) {
            if let first = fixes.first {
                VStack(spacing: 16) {
                    Image(uiImage: UIImage(cgImage: first.image))
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)

                    Text("Confidence \(Int(first.confidence * 100)) %")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("(\(fixes.count) left)")
                        .font(.caption2)

                    HStack {
                        TextField("Correct digit", text: $input)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            guard let val = Int(input),
                                  let firstFix = fixes.first
                            else { return }

                            SampleStore.shared.save(image: firstFix.image,
                                                    label: val)

                            // haptic feedback
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                            fixes.removeFirst()
                            input = ""
                            if fixes.isEmpty {
                                onFinish()
                            }
                        }
                        Button("Skip") {
                            fixes.removeFirst()
                            if fixes.isEmpty { onFinish() }
                        }
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .padding()
    }
}
