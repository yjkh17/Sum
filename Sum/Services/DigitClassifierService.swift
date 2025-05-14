
import Foundation
#if canImport(CoreML)
import CoreML
#endif

enum DigitClassifierService {
    /// Placeholder threshold; real model integration coming later.
    static let confidenceThreshold: Double = 0.80

    /// Dummy implementation so the project builds.
    /// Replace with Core ML model inference in the next iteration.
    static func predictDigit(from cgImage: CGImage) throws -> (digit: Int, confidence: Double)? {
        // TODO: load MLModel & run prediction
        return nil
    }
}
