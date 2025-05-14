
import SwiftUI
import RegexBuilder

/// نوع الأرقام المعتمد فى الجلسة (يحفظ فى ‎@AppStorage‎)
enum NumberSystem: String, CaseIterable, Identifiable, Codable {
    case western, eastern
    var id: String { rawValue }

    /// لغات Vision المناسبة
    var ocrLanguages: [String] {
        switch self {
        case .western: ["en", "handwriting"]
        case .eastern: ["ar", "handwriting"]
        }
    }

    /// الـ regex المقابل
    var regex: Regex<(Substring, Substring?)> {
        switch self {
        case .western:
            // 12,000   7,500.25   1234
            return try! Regex(#"(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?"#)
        case .eastern:
            // Eastern-Indic ٠-٩  / Arabic-Indic ۰-۹
            let digit = #"[٠-٩۰-۹]"#
            return try! Regex(#"(\#(digit){1,3}(?:,\#(digit){3})+|\#(digit)+)(\.\#(digit)+)?"#)
        }
    }
}
