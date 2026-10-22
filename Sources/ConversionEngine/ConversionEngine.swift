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
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
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
    
    private func safeDestination(for sourceURL: URL, newExtension: String, suffix: String? = nil) -> URL {
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = suffix != nil ? "\(name)_\(suffix!)" : name
        let targetDir = sourceURL.deletingLastPathComponent()
        
        // Teste Schreibrechte im Ursprungsverzeichnis (für Sandbox)
        if FileManager.default.isWritableFile(atPath: targetDir.path(percentEncoded: false)) {
            return targetDir.appendingPathComponent("\(baseName).\(newExtension)")
        } else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(baseName).\(newExtension)")
        }
    }
    
    public func optimizeImage(sourceURL: URL, targetURL: URL) async throws {
        try await ImageOptimizer.shared.stripMetadata(from: sourceURL, targetURL: targetURL)
    }
    
    /// Konvertiert ein Bild in das WebP-Format (mit verlustfreiem PNG-Fallback)
    public func convertToWebP(sourceURL: URL, destinationURL: URL? = nil) throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let dest = destinationURL ?? safeDestination(for: sourceURL, newExtension: "webp")
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
        let fallbackDest = destinationURL ?? safeDestination(for: sourceURL, newExtension: "png")
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
        let ext = sourceURL.pathExtension
        let dest = destinationURL ?? safeDestination(for: sourceURL, newExtension: ext, suffix: "Sanitized")
        try await ImageOptimizer.shared.stripMetadata(from: sourceURL, targetURL: dest)
        return dest
    }
}
