import SwiftUI

struct ResultCardView: View {
    let sum: Double
    let numbers: [Double]

    // Formatter so “478000” ⇒ “478,000”
    private var formatter: NumberFormatter {
        let nf          = NumberFormatter()
        nf.numberStyle  = .decimal
        nf.maximumFractionDigits = 2
        return nf
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // TOTAL
            Text("Total")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(formatter.string(from: sum as NSNumber) ?? "")
                .font(.system(size: 42, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            // LIST OF NUMBERS
            if !numbers.isEmpty {
                Divider()
                Text("Items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Wrap numbers in a simple flow-layout
                let indexed = numbers.enumerated().map { IndexedNumber(index: $0.offset, value: $0.element) }
                FlexibleView(data: indexed,
                             spacing: 8, alignment: .leading) { item in
                    let value = item.value
                    Text(formatter.string(from: value as NSNumber) ?? "")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        )
        .padding()
    }
}

// MARK: - Helper type to satisfy Hashable
private struct IndexedNumber: Hashable {
    let index: Int
    let value: Double
}

/// A simple flow-layout helper (very small)
fileprivate struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content

    init(data: Data,
         spacing: CGFloat = 8,
         alignment: HorizontalAlignment = .leading,
         @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data       = data
        self.spacing    = spacing
        self.alignment  = alignment
        self.content    = content
    }

    var body: some View {
        LazyVStack(alignment: alignment, spacing: spacing) {
            var width: CGFloat = 0
            var rows: [[Data.Element]] = [[]]

            // Greedy algo to wrap elements
            ForEach(Array(data), id: \.self) { element in
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let itemWidth = geo.size.width
                            if width + itemWidth + spacing > UIScreen.main.bounds.width - 32 { // padding
                                rows.append([element])
                                width = itemWidth + spacing
                            } else {
                                rows[rows.count - 1].append(element)
                                width += itemWidth + spacing
                            }
                        }
                }
                .frame(height: 0) // invisible
            }

            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { element in
                        content(element)
                    }
                }
            }
        }
    }
}
