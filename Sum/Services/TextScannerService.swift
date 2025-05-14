
import Vision

enum TextScannerService {
    /// Regex لاستخراج الأرقام (يدعم الكسور العشرية)
    private static let numberRegex = try! Regex(#"\d+(\.\d+)?"#)

    static func recognizeNumbers(in cgImage: CGImage) async throws -> [Double] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        try VNImageRequestHandler(cgImage: cgImage, options: [:])
            .perform([request])

        let observations = request.results ?? []
        var numbers: [Double] = []

        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            numbers.append(contentsOf: extractNumbers(from: text))
        }
        return numbers
    }

    private static func extractNumbers(from text: String) -> [Double] {
        text.matches(of: numberRegex).compactMap { match in
            Double(text[match.range])
        }
    }
}
