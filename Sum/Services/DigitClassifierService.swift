import Vision
import CoreML
import UIKit

enum DigitClassifierService {
    private static var vnModel: VNCoreMLModel? = nil
    private static var lastUsedDate: Date?
    private static let modelTimeout: TimeInterval = 300 // 5 minutes
    
    // MARK: - Model Management
    private static func loadModelIfNeeded() {
        guard vnModel == nil else { 
            lastUsedDate = Date()
            return 
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all // Use Neural Engine when available
            
            do {
                let model = try DigitClassifier(configuration: cfg).model
                vnModel = try VNCoreMLModel(for: model)
                lastUsedDate = Date()
                print("[DigitClassifier] Model loaded successfully")
            } catch {
                print("[DigitClassifier] Failed to load model:", error)
            }
        }
    }
    
    static func preloadModel() {
        loadModelIfNeeded()
    }
    
    static func cleanupIfNeeded() {
        // Release ML model if:
        // 1. We're in background OR
        // 2. Haven't used it for a while
        if UIApplication.shared.applicationState == .background ||
           (lastUsedDate.map { Date().timeIntervalSince($0) > modelTimeout } ?? false) {
            vnModel = nil
            print("[DigitClassifier] Model released from memory")
        }
    }

    // MARK: - Prediction
    static func predictDigit(from cgImage: CGImage) throws -> (Int, Double)? {
        guard let model = vnModel else {
            // Load synchronously if we haven't loaded yet
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let model = try DigitClassifier(configuration: cfg).model
            vnModel = try VNCoreMLModel(for: model)
            lastUsedDate = Date()
            return try predictWith(model: vnModel!, image: cgImage)
        }
        lastUsedDate = Date()
        return try predictWith(model: model, image: cgImage)
    }
    
    private static func predictWith(model: VNCoreMLModel, image: CGImage) throws -> (Int, Double)? {
        // Check cache first
        if let cached = SampleStore.getCachedDigit(for: image) {
            return (cached, 1.0)  // Cached results have 100% confidence
        }
        
        let req = VNCoreMLRequest(model: model)
        req.imageCropAndScaleOption = .scaleFill
        
        // Use high quality processing
        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: .up,
            options: [.ciContext: CIContext(options: [.cacheIntermediates: false])]
        )
        
        try handler.perform([req])
        guard let obs = req.results?.first as? VNClassificationObservation else { return nil }
        
        let digit = Int(obs.identifier) ?? -1
        
        // If confidence is high, cache the result
        if obs.confidence > 0.8 {
            SampleStore.save(image: image, as: digit)
        }
        
        return (digit, Double(obs.confidence))
    }
    
    // MARK: - Batch Processing
    static func predictDigits(from images: [CGImage], 
                            completion: @escaping ([(Int, Double)?]) -> Void) {
        // Process in batches to avoid memory pressure
        let batchSize = 5
        var results: [(Int, Double)?] = Array(repeating: nil, count: images.count)
        let queue = DispatchQueue(label: "com.sum.batchProcessing", qos: .userInitiated)
        let group = DispatchGroup()
        
        for i in stride(from: 0, to: images.count, by: batchSize) {
            let end = min(i + batchSize, images.count)
            let batch = Array(images[i..<end])
            
            group.enter()
            queue.async {
                for (j, image) in batch.enumerated() {
                    autoreleasepool {
                        do {
                            results[i + j] = try predictDigit(from: image)
                        } catch {
                            print("[DigitClassifier] Failed to process image:", error)
                        }
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(results)
        }
    }
}
