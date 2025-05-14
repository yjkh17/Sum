

import SwiftUI

struct FixDigitSheet: View {
    @Binding var fixes: [FixCandidate]          // live queue
    var onFinish: () -> Void                    // callback when queue empty

    @State private var input = ""

    var body: some View {
        VStack(spacing: 24) {
            if let first = fixes.first {
                Image(decorative: first.image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 64, height: 64)
                    .border(Color.yellow)

                TextField("Digit", text: $input)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    if let n = Int(input) {
                        SampleStore.shared.save(image: first.image, label: n)
                        fixes.removeFirst()
                        input = ""
                        if fixes.isEmpty { onFinish() }
                    }
                }
                .disabled(Int(input) == nil)
            } else {
                ProgressView()
            }
        }
        .padding()
    }
}

