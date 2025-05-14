import SwiftUI

/// A translucent overlay that shows the live total while scanning.
struct LiveOverlayView: View {
    let numbers: [Double]

    var body: some View {
        VStack {
            Spacer()   // push the label to the bottom
            Text("Total: \(numbers.reduce(0, +), format: .number)")
                .font(.title2.bold())
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 20)   // extra space above the Home indicator
    }
}
