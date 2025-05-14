
import SwiftUI

/// Shows cropped image (if saved) + the numbers card.
struct RecordDetailView: View {
    let record: ScanRecord
    let image: UIImage?

    var body: some View {
        ScrollView {
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .padding()
            }

            ResultCardView(sum: record.total,
                           numbers: record.numbers)
        }
        .navigationTitle(
            record.date.formatted(date: .abbreviated, time: .shortened)
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}
