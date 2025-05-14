import Vision

// MARK: - NumberObservation
/// One detected number and its CGRect in image-space (pixels)
struct NumberObservation: Identifiable, Hashable {
    let id = UUID()
    let value: Double
    let rect: CGRect     // in pixel coordinates
}

enum TextScannerService {
    /// أرقام قد تحتوى على فواصل آلاف «12,000» أو كسور «7,500.50»
    /// مثال للـregex:  1,234   12,000   7500   7,500.50   123.45
    private static let numberRegex = try! Regex(#"(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?"#)

    static func recognizeNumbers(in cgImage: CGImage) async throws -> [Double] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

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
            let raw = String(text[match.range])
            let clean = raw.replacingOccurrences(of: ",", with: "")
            return Double(clean)
        }
    }

    // MARK: - New helper returning value+rect
    static func recognizeNumberObservations(in cgImage: CGImage) async throws -> [NumberObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        try VNImageRequestHandler(cgImage: cgImage, options: [:])
            .perform([request])

        let observations = request.results ?? []
        var result: [NumberObservation] = []

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        for obs in observations {
            guard let str = obs.topCandidates(1).first?.string else { continue }

            for match in str.matches(of: numberRegex) {
                let raw   = String(str[match.range])
                let clean = raw.replacingOccurrences(of: ",", with: "")
                guard let val = Double(clean) else { continue }

                // VN observation’s boundingBox is in unit space, flip Y
                let box = obs.boundingBox
                let rect = CGRect(
                    x: box.minX * imgW,
                    y: (1 - box.maxY) * imgH,
                    width: box.width * imgW,
                    height: box.height * imgH
                )
                result.append(.init(value: val, rect: rect))
            }
        }
        return result
    }
}
