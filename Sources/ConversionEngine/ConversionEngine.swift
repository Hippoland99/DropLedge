import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import AVFoundation
import PDFKit

public actor ImageOptimizer {
    public static let shared = ImageOptimizer()
    private init() {}
    
    public func stripMetadata(from sourceURL: URL, targetURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let uti = CGImageSourceGetType(source) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, uti, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        // Vollständiges Bereinigen der Exif/TIFF/GPS Dictionaries
        let emptyProperties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [:] as [String: Any],
            kCGImagePropertyGPSDictionary: [:] as [String: Any],
            kCGImagePropertyTIFFDictionary: [:] as [String: Any]
        ]
        
        CGImageDestinationAddImageFromSource(destination, source, 0, emptyProperties as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

public actor ConversionEngine {
    public static let shared = ConversionEngine()
    private init() {}
    
    public func optimizeImage(sourceURL: URL, targetURL: URL) async throws {
        try await ImageOptimizer.shared.stripMetadata(from: sourceURL, targetURL: targetURL)
    }
    
    /// Konvertiert ein Bild in das WebP-Format (mit verlustfreiem PNG-Fallback)
    public func convertToWebP(sourceURL: URL, destinationURL: URL? = nil) throws -> URL {
        let dest = destinationURL ?? sourceURL.deletingPathExtension().appendingPathExtension("webp")
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let typeIdentifier = ("org.webmproject.webp" as CFString)
        if let destination = CGImageDestinationCreateWithURL(dest as CFURL, typeIdentifier, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            if CGImageDestinationFinalize(destination) {
                return dest
            }
        }
        
        // Fallback: Optimiertes PNG
        let fallbackDest = sourceURL.deletingPathExtension().appendingPathExtension("png")
        if let destination = CGImageDestinationCreateWithURL(fallbackDest as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            if CGImageDestinationFinalize(destination) {
                return fallbackDest
            }
        }
        throw CocoaError(.fileWriteUnknown)
    }
    
    /// Entfernt alle EXIF/GPS/TIFF Metadaten und erzeugt eine bereinigte Kopie
    public func stripEXIFMetadata(sourceURL: URL, destinationURL: URL? = nil) async throws -> URL {
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let dest = destinationURL ?? sourceURL.deletingLastPathComponent().appendingPathComponent("\(name)_Sanitized.\(ext)")
        try await ImageOptimizer.shared.stripMetadata(from: sourceURL, targetURL: dest)
        return dest
    }
}
