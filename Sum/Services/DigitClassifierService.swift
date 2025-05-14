import Vision
import CoreML

enum DigitClassifierService {
    private static let vnModel: VNCoreMLModel = {
        let cfg = MLModelConfiguration()
        let model = try! DigitClassifier(configuration: cfg).model
        return try! VNCoreMLModel(for: model)
    }()

    static func predictDigit(from cgImage: CGImage) throws -> (Int, Double)? {
        let req = VNCoreMLRequest(model: vnModel)
        req.imageCropAndScaleOption = .scaleFill      // يضبط المقاس

        try VNImageRequestHandler(cgImage: cgImage).perform([req])
        guard let obs = req.results?.first as? VNClassificationObservation else { return nil }

        return (Int(obs.identifier) ?? -1, Double(obs.confidence))
    }
}
