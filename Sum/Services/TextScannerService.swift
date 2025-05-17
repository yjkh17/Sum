import Vision
import Foundation

// MARK: - NumberObservation
struct NumberObservation: Identifiable, Hashable {
    let id = UUID()
    let value: Double
    let rect: CGRect     // in pixel coordinates
    let confidence: Float
}

// MARK: - FixCandidate
struct FixCandidate: Identifiable {
    let id = UUID()
    let image: CGImage      // cropped digit image
    let rect: CGRect       // location in source image
    var suggested: Int?     // Vision/CoreML suggestion
    let confidence: Float   // 0...1

    // Convenience init for Live-OCR
    init(image: CGImage,
         rect:  CGRect,
         suggested: Int?,
         confidence: Float)
    {
        self.image       = image
        self.rect        = rect
        self.suggested   = suggested
        self.confidence  = confidence
    }
}

enum TextScannerService {
    static var currentSystem: NumberSystem = .western
    
    // MARK: - Constants
    private enum Confidence {
        static let lowThreshold: Float = 0.30
        static let mediumThreshold: Float = 0.60
        static let highThreshold: Float = 0.80
    }

    // MARK: - Character Conversion
    private static let east2west: [Character: Character] = [
        "٠":"0","١":"1","٢":"2","٣":"3","٤":"4",
        "٥":"5","٦":"6","٧":"7","٨":"8","٩":"9",
        "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4",
        "۵":"5","۶":"6","۷":"7","۸":"8","۹":"9"
    ]
    
    static func normalize(_ s: String) -> String {
        String(s.map { east2west[$0] ?? $0 })
    }

    // MARK: - Core Recognition
    /// أرقام قد تحتوى على فواصل آلاف «12,000» أو كسور «7,500.50»
    /// مثال للـregex:  1,234   12,000   7500   7,500.50   123.45
    static func recognizeNumbers(in cgImage: CGImage) async throws -> [Double] {
        let request = makeTextRequest()
        try await performRequest(request, on: cgImage)
        return extractNumbers(from: request.results ?? [])
    }
    
    // MARK: - Advanced Recognition
    static func recognizeNumberObservations(in cgImage: CGImage)
    async throws -> ([NumberObservation], [FixCandidate]) {
        let request = makeTextRequest()
        try await performRequest(request, on: cgImage)
        return processObservations(request.results ?? [], in: cgImage)
    }
    
    // MARK: - Private Helpers
    private static func makeTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = currentSystem.ocrLanguages
        return request
    }
    
    private static func performRequest(_ request: VNRecognizeTextRequest, on image: CGImage) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try VNImageRequestHandler(cgImage: image, options: [:])
                    .perform([request])
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private static func extractNumbers(from observations: [VNRecognizedTextObservation]) -> [Double] {
        observations.flatMap { obs -> [Double] in
            guard let text = obs.topCandidates(1).first?.string else { return [] }
            return extractNumbers(from: text)
        }
    }
    
    private static func extractNumbers(from text: String) -> [Double] {
        text.matches(of: currentSystem.regex).compactMap { match in
            var raw = String(text[match.range])
                .replacingOccurrences(of: ",", with: "")
            if currentSystem == .eastern {
                raw = normalize(raw)
            }
            return Double(raw)
        }
    }
    
    private static func processObservations(_ observations: [VNRecognizedTextObservation], in image: CGImage) -> ([NumberObservation], [FixCandidate]) {
        // Use capacity hint for better array performance
        var result = [NumberObservation]()
        result.reserveCapacity(observations.count)
        var fixes = [FixCandidate]()
        fixes.reserveCapacity(observations.count / 2)
        
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        
        for obs in observations {
            guard let str = obs.topCandidates(1).first?.string else { continue }
            
            // Process all matches in one pass
            let matches = str.matches(of: currentSystem.regex)
            let processedMatches = matches.compactMap { match -> (Double, CGRect)? in
                guard let (val, rect) = processMatch(match, in: str, observation: obs, imageSize: CGSize(width: imgW, height: imgH)) else { return nil }
                return (val, rect)
            }
            
            for (val, rect) in processedMatches {
                let confidence = obs.confidence
                
                // Try CoreML only if really needed
                if shouldTryMLRefinement(confidence: confidence),
                   let (mlDigit, mlConf) = tryMLRefinement(for: rect, in: image) {
                    let newConf = max(confidence, Float(mlConf))
                    result.append(.init(value: Double(mlDigit), rect: rect, confidence: newConf))
                    continue
                }
                
                result.append(.init(value: val, rect: rect, confidence: confidence))
                
                if shouldAddFixCandidate(confidence: confidence),
                   let cropped = image.cropping(to: rect.integral) {
                    fixes.append(.init(image: cropped,
                                     rect: rect,
                                     suggested: Int(val),
                                     confidence: confidence))
                }
            }
        }
        
        return (result, fixes)
    }
    
    private static func processMatch(_ match: Regex<Substring>.Match, in text: String, observation: VNRecognizedTextObservation, imageSize: CGSize) -> (value: Double, rect: CGRect)? {
        var raw = String(text[match.range])
            .replacingOccurrences(of: ",", with: "")
        if currentSystem == .eastern {
            raw = normalize(raw)
        }
        guard let val = Double(raw) else { return nil }
        
        let box = observation.boundingBox
        let rect = CGRect(
            x: box.minX * imageSize.width,
            y: (1 - box.maxY) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
        
        return (val, rect)
    }
    
    private static func shouldTryMLRefinement(confidence: Float) -> Bool {
        confidence < Confidence.mediumThreshold && currentSystem == .western
    }
    
    private static func tryMLRefinement(for rect: CGRect, in image: CGImage) -> (digit: Int, confidence: Double)? {
        guard let crop = image.cropping(to: rect.integral),
              let (digit, confidence) = try? DigitClassifierService.predictDigit(from: crop),
              Float(confidence) > Confidence.highThreshold else {
            return nil
        }
        return (digit, confidence)
    }
    
    private static func shouldAddFixCandidate(confidence: Float) -> Bool {
        confidence < Confidence.lowThreshold
    }
}
