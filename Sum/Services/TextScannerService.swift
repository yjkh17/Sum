import Vision
import Foundation

// MARK: - NumberObservation
struct NumberObservation: Identifiable, Hashable {
    let id = UUID()
    let value: Double
    let rect: CGRect     // in pixel coordinates
    let confidence: Float
}

// MARK: - FixCandidate (رقم منخفض الثقة يحتاج تصحيح)
struct FixCandidate: Identifiable {
    let id = UUID()
    let image: CGImage      // صورة القصاصة
    let rect : CGRect       // مكانها فى الصورة الأصليّة
    var suggested: Int?     // ما اقترحه Vision / CoreML
    let confidence: Float
}

// يُحدَّث من الـ ViewModel
enum TextScannerService {
    static var currentSystem: NumberSystem = .western

    // regex مشتقّ من الاختيار الحالى (النوع الجديد Regex<Substring>)
    private static var numberRegex: Regex<Substring> {
        currentSystem.regex
    }

    // خريطة التحويل ٠→0 … إلخ
    private static let east2west: [Character: Character] = [
        "٠":"0","١":"1","٢":"2","٣":"3","٤":"4",
        "٥":"5","٦":"6","٧":"7","٨":"8","٩":"9",
        "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4",
        "۵":"5","۶":"6","۷":"7","۸":"8","۹":"9"
    ]
    static func normalize(_ s: String) -> String {
        String(s.map { east2west[$0] ?? $0 })
    }

    /// أرقام قد تحتوى على فواصل آلاف «12,000» أو كسور «7,500.50»
    /// مثال للـregex:  1,234   12,000   7500   7,500.50   123.45
    static func recognizeNumbers(in cgImage: CGImage) async throws -> [Double] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages   = currentSystem.ocrLanguages

        try VNImageRequestHandler(cgImage: cgImage, options: [:])
            .perform([request])

        let observations = request.results ?? []
        print("[OCR] Observations count = \(observations.count)")   // DEBUG
        var numbers: [Double] = []

        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            print("[OCR] Line: “\(text)”")                           // DEBUG
            numbers.append(contentsOf: extractNumbers(from: text))
        }
        print("[OCR] Extracted numbers = \(numbers)")                // DEBUG
        return numbers
    }

    private static func extractNumbers(from text: String) -> [Double] {
        let rawMatches = text.matches(of: numberRegex)
        return rawMatches.compactMap { match in
            // احصل على السلسلة المطابقة ثم أزل الفواصل قبل التحويل إلى ‎Double‎
            var raw = String(text[match.range])
            raw     = raw.replacingOccurrences(of: ",", with: "")
            if currentSystem == .eastern { raw = normalize(raw) }
            let clean = raw
            return Double(clean)
        }
    }

    // MARK: - New helper returning value+rect
    static func recognizeNumberObservations(in cgImage: CGImage)
    async throws -> ([NumberObservation], [FixCandidate]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages   = currentSystem.ocrLanguages

        try VNImageRequestHandler(cgImage: cgImage, options: [:])
            .perform([request])

        let observations = request.results ?? []
        var result : [NumberObservation] = []
        var fixes  : [FixCandidate]      = []

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        for obs in observations {
            guard let str = obs.topCandidates(1).first?.string else { continue }

            for match in str.matches(of: numberRegex) {
                var raw = String(str[match.range])
                raw     = raw.replacingOccurrences(of: ",", with: "")
                if currentSystem == .eastern { raw = normalize(raw) }
                let clean = raw

                guard let val = Double(clean) else { continue }

                // --- Bounding box (pixel coordinates) for this VNTextObservation ---
                let box = obs.boundingBox
                let rect = CGRect(
                    x: box.minX * imgW,
                    y: (1 - box.maxY) * imgH,
                    width: box.width  * imgW,
                    height: box.height * imgH
                )

                // --------- Fallback → Core-ML لتحسين الثقة ---------
                var conf = obs.confidence
                if obs.confidence < 0.60,                          // Vision متردد
                   currentSystem == .western,                      // يدعم الغربية حالياً
                   let crop = cgImage.cropping(to: rect.integral),
                   let (digit, mlConf) =
                        try? DigitClassifierService.predictDigit(from: crop),
                   mlConf > 0.80 {                                 // الموديل واثق
                    conf  = max(conf, Float(mlConf))
                    result.append(.init(value: Double(digit),
                                       rect: rect,
                                       confidence: conf))
                    continue                                       // تخطِّ Vision
                }
                // --------------------------------------------------------------------

                // VN observation’s boundingBox is in unit space, flip Y (already done above)
                result.append(.init(value: val, rect: rect, confidence: conf))

                // ✦ مرشَّح للتصحيح إذا الثقة < 0.30
                if obs.confidence < 0.30,
                   let sub = cgImage.cropping(to: rect.integral) {
                    fixes.append(.init(image: sub,
                                       rect: rect,
                                       suggested: Int(val),
                                       confidence: conf))
                }
            }
        }
        return (result, fixes)
    }
}
