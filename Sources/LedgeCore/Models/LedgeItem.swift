import Foundation
import UniformTypeIdentifiers

public struct LedgeItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let originalURL: URL?
    public var savedURL: URL?
    public let timestamp: Date
    public let contentType: UTType
    public let suggestedFileName: String
    public var extractedText: String?
    public var tags: [String]
    public var originalSizeBytes: Int64?
    
    public var fileURL: URL? {
        savedURL ?? originalURL
    }
    
    public var currentFileSizeBytes: Int64? {
        guard let url = fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    public var hasSavings: Bool {
        guard let current = currentFileSizeBytes,
              let original = originalSizeBytes,
              original > current,
              original > 0 else {
            return false
        }
        let savedPct = Int((Double(original - current) / Double(original)) * 100.0)
        return savedPct >= 3
    }
    
    public var sizeSavingsBadge: String? {
        guard let current = currentFileSizeBytes else { return nil }
        let currentFormatted = ByteCountFormatter.string(fromByteCount: current, countStyle: .file)
        
        if let original = originalSizeBytes, original > current, original > 0 {
            let savedPct = Int((Double(original - current) / Double(original)) * 100.0)
            if savedPct >= 3 {
                return "\(currentFormatted) (-\(savedPct)%)"
            }
        }
        return currentFormatted
    }
    
    public init(
        id: UUID = UUID(),
        originalURL: URL? = nil,
        savedURL: URL? = nil,
        timestamp: Date = Date(),
        contentType: UTType,
        suggestedFileName: String,
        extractedText: String? = nil,
        tags: [String] = [],
        originalSizeBytes: Int64? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.savedURL = savedURL
        self.timestamp = timestamp
        self.contentType = contentType
        self.suggestedFileName = suggestedFileName
        self.extractedText = extractedText
        self.tags = tags
        self.originalSizeBytes = originalSizeBytes
    }
}
