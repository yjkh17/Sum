import SwiftUI

struct ResultCardView: View {
    let sum: Double
    let numbers: [Double]
    private let indexed: [IndexedNumber]
    private let formatter: NumberFormatter
    @State private var isAnimating = false

    init(sum: Double, numbers: [Double]) {
        self.sum      = sum
        self.numbers  = numbers
        self.indexed  = numbers.enumerated().map { .init(index: $0, value: $1) }

        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        self.formatter = nf
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Total Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 10)

                Text(formatter.string(from: sum as NSNumber) ?? "")
                    .font(.system(size: 42, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .opacity(isAnimating ? 1 : 0)
                    .scaleEffect(isAnimating ? 1 : 0.8, anchor: .leading)
            }

            // MARK: - Items Section
            if !numbers.isEmpty {
                Divider()
                    .opacity(isAnimating ? 1 : 0)
                
                Text("Items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 10)

                // Wrap numbers in a simple flow-layout
                FlexibleView(data: indexed, spacing: 8, alignment: .leading) { item in
                    Text(formatter.string(from: item.value as NSNumber) ?? "")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.1))
                        )
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(
                            .spring(dampingFraction: 0.7)
                            .delay(Double(item.index) * 0.05),
                            value: isAnimating
                        )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(
                    color: .black.opacity(0.1),
                    radius: 15,
                    x: 0,
                    y: 5
                )
        )
        .padding()
        .onAppear {
            withAnimation(.spring(dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
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
