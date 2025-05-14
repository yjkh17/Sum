import Foundation
import SwiftData

@Model
final class ScanRecord {
    @Attribute(.unique) var id = UUID()
    var date   = Date()
    var total  : Double = 0
    var numbers: [Double] = []
    var imagePath: String? = nil

    // SwiftData’s @Model needs an explicit initializer when we add defaulted properties.
    init(date: Date = .now,
         total: Double = 0,
         numbers: [Double] = [],
         imagePath: String? = nil)
    {
        self.date       = date
        self.total      = total
        self.numbers    = numbers
        self.imagePath  = imagePath
    }
}
