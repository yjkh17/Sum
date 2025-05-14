
import Foundation
import SwiftData

@Model
final class ScanRecord {
    @Attribute(.unique) var id = UUID()
    var date   = Date()
    var total  : Double = 0
    var numbers: [Double] = []
    var imagePath: String? = nil
}
