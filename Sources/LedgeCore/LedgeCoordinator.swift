import Foundation
import AppKit
import UniformTypeIdentifiers
import StorageCoordinator
import VisionEngine
import ConversionEngine
import CodeAnalysis

public actor LedgeCoordinator {
    public static let shared = LedgeCoordinator()
    
    private let storage = StorageCoordinator.shared
    private let vision = VisionEngine.shared
    private let converter = ConversionEngine.shared
    private let omniConverter = OmniConverterEngine.shared
    private let optimizer = ImageOptimizer.shared
    
    private init() {}
    
    /// Verarbeitet abgelegten Text / Code
    public func processDroppedText(
        _ text: String,
        baseDirectory: URL,
        sourceApp: String? = "DropLedge"
    ) async throws -> URL {
        let classification = CodeClassifier.classify(rawText: text)
        let isPlainText = classification.fileExtension == "txt"
        let category: StorageCategory = isPlainText ? .rawText : .code
        let typeName = isPlainText ? "ClipboardNote" : "CodeSnippet"
        
        guard let data = classification.cleanedContent.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        
        return try await storage.persistCategorized(
            data: data,
            baseDirectory: baseDirectory,
            category: category,
            typeName: typeName,
            sourceApp: sourceApp,
            fileExtension: classification.fileExtension,
            spotlightComment: classification.cleanedContent
        )
    }
    
    /// Speichert ein Text- oder Code-Snippet mit spezifischem Dateinamen und Endung im Text & Code Studio
    public func saveSnippet(
        text: String,
        fileName: String,
        fileExtension: String,
        baseDirectory: URL,
        sourceApp: String? = "TextCodeStudio"
    ) async throws -> URL {
        let cleanExt = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let safeExt = cleanExt.isEmpty ? "txt" : cleanExt
        
        var finalName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalName.isEmpty {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            finalName = "Snippet_\(df.string(from: Date()))"
        }
        if !finalName.lowercased().hasSuffix(".\(safeExt)") {
            finalName = "\(finalName).\(safeExt)"
        }
        
        let isRaw = ["txt", "env", "log"].contains(safeExt)
        let subFolder = isRaw ? "RawText" : "Code"
        
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        
        return try await storage.persist(
            data: data,
            baseDirectory: baseDirectory,
            subFolder: subFolder,
            fileName: finalName,
            spotlightComment: text,
            sourceApplication: sourceApp ?? "TextCodeStudio"
        )
    }
    
    /// Verarbeitet abgelegte Bild-Daten und extrahiert Text via VisionEngine
    public func processDroppedImage(
        data: Data,
        fileExtension: String = "png",
        baseDirectory: URL,
        sourceApp: String? = "ScreenCapture"
    ) async throws -> (savedURL: URL, ocrText: String?) {
        var detectedText: String? = nil
        
        do {
            let result = try await vision.recognizeText(from: data)
            detectedText = result.fullText
        } catch {
            detectedText = nil
        }
        
        let typeName = detectedText != nil ? "ScreenCapture" : "Image"
        
        let savedURL = try await storage.persistCategorized(
            data: data,
            baseDirectory: baseDirectory,
            category: .media,
            typeName: typeName,
            sourceApp: sourceApp,
            fileExtension: fileExtension,
            spotlightComment: detectedText
        )
        
        return (savedURL, detectedText)
    }
    
    /// Verarbeitet eine gedroppte Dateipfad-URL (Finder, Desktop, etc.)
    public func processDroppedFileURL(
        _ url: URL,
        baseDirectory: URL,
        sourceApp: String? = nil
    ) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        let app = sourceApp ?? "Finder"
        
        // 1. Bild-Verarbeitung
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif", "bmp"]
        if imageExtensions.contains(ext) {
            let data = try Data(contentsOf: url)
            let result = try await processDroppedImage(
                data: data,
                fileExtension: ext,
                baseDirectory: baseDirectory,
                sourceApp: app
            )
            return result.savedURL
        }
        
        // 2. Video-Verarbeitung
        let videoExtensions = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
        if videoExtensions.contains(ext) {
            let data = try Data(contentsOf: url)
            let typeName = url.deletingPathExtension().lastPathComponent
            return try await storage.persistCategorized(
                data: data,
                baseDirectory: baseDirectory,
                category: .media,
                typeName: typeName,
                sourceApp: app,
                fileExtension: ext,
                spotlightComment: "Video Media"
            )
        }
        
        // 3. Code- und Text-Verarbeitung
        let codeExtensions = [
            "swift", "py", "json", "sh", "zsh", "bash", "md", "txt",
            "c", "cpp", "h", "rs", "go", "js", "ts", "html", "css", "sql"
        ]
        if codeExtensions.contains(ext) {
            let content = try String(contentsOf: url, encoding: .utf8)
            return try await processDroppedText(content, baseDirectory: baseDirectory, sourceApp: app)
        }
        
        // 4. Dokumente (PDF, etc.)
        let data = try Data(contentsOf: url)
        let category: StorageCategory = .documents
        let typeName = url.deletingPathExtension().lastPathComponent
        
        return try await storage.persistCategorized(
            data: data,
            baseDirectory: baseDirectory,
            category: category,
            typeName: typeName,
            sourceApp: app,
            fileExtension: ext,
            spotlightComment: nil
        )
    }
    
    /// Speichert den aktuellen Inhalt der macOS-Zwischenablage ohne Fensterinteraktion
    public func quickSaveClipboard(baseDirectory: URL) async throws -> URL? {
        let pasteboard = NSPasteboard.general
        
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstURL = urls.first {
            return try await processDroppedFileURL(firstURL, baseDirectory: baseDirectory, sourceApp: "Clipboard")
        }
        
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let result = try await processDroppedImage(
                data: pngData,
                fileExtension: "png",
                baseDirectory: baseDirectory,
                sourceApp: "Clipboard"
            )
            return result.savedURL
        }
        
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return try await processDroppedText(text, baseDirectory: baseDirectory, sourceApp: "Clipboard")
        }
        
        return nil
    }
    
    // MARK: - OmniConverter Video Operations
    
    public func convertToWebMP4(url: URL) async throws -> URL {
        return try await omniConverter.convertToWebMP4(sourceURL: url)
    }
    
    public func convertToAnimatedGIF(url: URL, fps: Int = 15) async throws -> URL {
        return try await omniConverter.convertToAnimatedGIF(sourceURL: url, fps: fps)
    }
    
    public func compressVideoForDiscord(url: URL) async throws -> URL {
        return try await omniConverter.compressVideoToTargetSize(sourceURL: url, targetMB: 24.0)
    }
    
    public func compressVideoToTargetSize(url: URL, targetMB: Double) async throws -> URL {
        return try await omniConverter.compressVideoToTargetSize(sourceURL: url, targetMB: targetMB)
    }
    
    public func trimVideo(url: URL, startTime: Double, endTime: Double) async throws -> URL {
        return try await omniConverter.trimVideo(sourceURL: url, startTime: startTime, endTime: endTime)
    }
    
    public func extractAudio(url: URL) async throws -> URL {
        return try await omniConverter.extractAudio(sourceURL: url)
    }
    
    // MARK: - OmniConverter Image Operations
    
    public func cropImage(url: URL, aspectRatio: OmniConverterEngine.AspectRatioPreset) async throws -> URL {
        return try await omniConverter.cropImage(sourceURL: url, aspectRatio: aspectRatio)
    }
    
    public func resizeImage(url: URL, scale: Double? = nil, maxWidth: CGFloat? = nil) async throws -> URL {
        return try await omniConverter.resizeImage(sourceURL: url, scale: scale, maxWidth: maxWidth)
    }
    
    public func compressImage(url: URL, quality: Double, targetFormat: OmniConverterEngine.ImageTargetFormat? = nil) async throws -> URL {
        return try await omniConverter.compressImage(sourceURL: url, quality: quality, targetFormat: targetFormat)
    }
    
    public func convertImage(url: URL, to format: OmniConverterEngine.ImageTargetFormat) async throws -> URL {
        return try await omniConverter.convertImage(sourceURL: url, targetFormat: format)
    }
    
    public func convertToCustomFormat(url: URL, targetExtension: String) async throws -> URL {
        return try await omniConverter.convertToCustomFormat(sourceURL: url, targetExtension: targetExtension)
    }
    
    public func stripMetadata(url: URL) async throws -> URL {
        return try await converter.stripEXIFMetadata(sourceURL: url, destinationURL: nil)
    }
    
    public func extractOCRText(from url: URL) async throws -> String {
        let data = try Data(contentsOf: url)
        let result = try await vision.recognizeText(from: data)
        return result.fullText
    }
    
    public func isVideo(url: URL) async -> Bool {
        await omniConverter.isVideo(url: url)
    }
    
    public func isImage(url: URL) async -> Bool {
        await omniConverter.isImage(url: url)
    }
    
    // MARK: - OmniConverter PDF Operations
    
    public func compressPDF(url: URL, maxDPI: CGFloat = 150, quality: CGFloat = 0.65) async throws -> URL {
        return try await omniConverter.compressPDF(sourceURL: url, maxDPI: maxDPI, quality: quality)
    }
    
    public func extractPDFPages(url: URL, pageSelection: String) async throws -> URL {
        return try await omniConverter.extractPages(sourceURL: url, pageSelection: pageSelection)
    }
    
    public func extractFirstPDFPage(url: URL) async throws -> URL {
        return try await omniConverter.extractFirstPage(sourceURL: url)
    }
    
    public func isPDF(url: URL) async -> Bool {
        await omniConverter.isPDF(url: url)
    }
}
