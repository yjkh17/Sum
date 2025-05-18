import SwiftUI
import RegexBuilder
import _StringProcessing        // RegexBuilder internals

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

    /// ‎Regex‎ خالٍ من *المجموعات القابلة للاصطياد* حتى لا نحتاج
    /// النوع المركّب `(Substring, Substring?)` مع استخدام raw strings ومعالجة الأخطاء بدلًا من `try!`.
    var regex: Regex<Substring> {
        switch self {
        case .western:
            // أمثلة: 1,234   7500   12,000.50
            let pattern = #"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#
            return (try? Regex(pattern)) ?? Regex { "" }
        case .eastern:
            // Eastern-Indic ٠-٩ + Arabic-Indic ۰-۹
            let d = #"[٠-٩۰-۹]"#
            // أمثلة: ١٢٣   ١٢٬٣٤٥٫٦٧   ۱۲٬۸۰۰
            let pattern = #"(?:(?:\#(d){1,3}(?:,\#(d){3})+|\#(d)+)(?:\.\#(d)+)?)"#
            return (try? Regex(pattern)) ?? Regex { "" }
        }
    }
}
