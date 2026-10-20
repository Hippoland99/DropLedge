import Foundation
import Vision
import CoreGraphics
import ImageIO

public actor VisionEngine {
    public static let shared = VisionEngine()
    private init() {}
    
    public enum VisionError: Error, Sendable, Equatable {
        case executionFailed
        case noTextDetected
        case invalidImageData
    }
    
    public struct RecognitionResult: Sendable, Equatable {
        public let fullText: String
        public let confidence: Float
        public let lineCount: Int
        
        public init(fullText: String, confidence: Float, lineCount: Int) {
            self.fullText = fullText
            self.confidence = confidence
            self.lineCount = lineCount
        }
    }
    
    /// Führt die Offline-Texterkennung auf einem CGImage via Vision.framework aus
    public func recognizeText(
        from cgImage: CGImage,
        languages: [String] = ["de-DE", "en-US"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) throws -> RecognitionResult {
        var recognizedStrings: [String] = []
        var totalConfidence: Float = 0.0
        var blockCount: Int = 0
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else {
            throw VisionError.noTextDetected
        }
        
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            recognizedStrings.append(topCandidate.string)
            totalConfidence += topCandidate.confidence
            blockCount += 1
        }
        
        guard !recognizedStrings.isEmpty else {
            throw VisionError.noTextDetected
        }
        
        let finalConfidence = blockCount > 0 ? (totalConfidence / Float(blockCount)) : 0.0
        let fullText = recognizedStrings.joined(separator: "\n")
        
        return RecognitionResult(
            fullText: fullText,
            confidence: finalConfidence,
            lineCount: blockCount
        )
    }
    
    /// Convenience-Methode zur direkten Texterkennung aus Bild-Rohdaten (PNG, JPEG, etc.)
    public func recognizeText(
        from imageData: Data,
        languages: [String] = ["de-DE", "en-US"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) throws -> RecognitionResult {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw VisionError.invalidImageData
        }
        
        return try recognizeText(from: cgImage, languages: languages, recognitionLevel: recognitionLevel)
    }
}
