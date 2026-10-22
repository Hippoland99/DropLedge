import Foundation
import AVFoundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import AppKit
import PDFKit

public actor OmniConverterEngine {
    public static let shared = OmniConverterEngine()
    private init() {}
    
    // MARK: - Aspect Ratio & Presets
    
    public enum AspectRatioPreset: String, Sendable, CaseIterable {
        case square = "1:1"
        case landscape16_9 = "16:9"
        case portrait9_16 = "9:16"
    }
    
    public enum ImageTargetFormat: String, Sendable, CaseIterable {
        case png = "png"
        case jpeg = "jpeg"
        case heic = "heic"
        case webp = "webp"
        case tiff = "tiff"
        case bmp = "bmp"
    }
    
    // MARK: - Safe Destination Helper (App Sandbox)
    
    public func safeDestination(for sourceURL: URL, suffix: String? = nil, newExtension: String? = nil) -> URL {
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let ext = newExtension ?? sourceURL.pathExtension
        let baseName = suffix != nil ? "\(name)_\(suffix!)" : name
        let targetDir = sourceURL.deletingLastPathComponent()
        
        if FileManager.default.isWritableFile(atPath: targetDir.path(percentEncoded: false)) {
            return targetDir.appendingPathComponent("\(baseName).\(ext)")
        } else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(baseName).\(ext)")
        }
    }
    
    // MARK: - Video Studio (Trim & Compression)
    
    /// Video trimmen (Trim) via AVAssetExportSession und CMTimeRange
    public func trimVideo(
        sourceURL: URL,
        startTime: Double,
        endTime: Double,
        destinationURL: URL? = nil
    ) async throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        
        let start = max(0.0, min(startTime, totalSeconds))
        let end = min(totalSeconds, max(start + 0.1, endTime))
        let timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        
        let ext = sourceURL.pathExtension
        let dest = destinationURL ?? safeDestination(for: sourceURL, suffix: "Trimmed", newExtension: ext)
        
        let preset = AVAssetExportPresetPassthrough
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) ??
                                  AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        exportSession.outputURL = dest
        exportSession.outputFileType = (ext.lowercased() == "mp4") ? .mp4 : .mov
        exportSession.timeRange = timeRange
        
        if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: dest)
        }
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return dest
        } else {
            throw exportSession.error ?? CocoaError(.fileWriteUnknown)
        }
    }
    
    /// Smarte Video-Kompression auf eine Zielgröße (z. B. 25 MB für Discord/Slack oder 10 MB für E-Mail)
    public func compressVideoToTargetSize(
        sourceURL: URL,
        targetMB: Double,
        destinationURL: URL? = nil
    ) async throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let tag = targetMB <= 10.0 ? "Email10MB" : "Discord25MB"
        let dest = destinationURL ?? safeDestination(for: sourceURL, suffix: tag, newExtension: "mp4")
        let asset = AVURLAsset(url: sourceURL)
        
        let preset: String
        if targetMB <= 10.0 {
            preset = AVAssetExportPresetMediumQuality
        } else {
            preset = AVAssetExportPreset1280x720
        }
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        exportSession.outputURL = dest
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: dest)
        }
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return dest
        } else {
            throw exportSession.error ?? CocoaError(.fileWriteUnknown)
        }
    }
    
    /// Konvertiert in optimiertes Web-MP4
    public func convertToWebMP4(sourceURL: URL, destinationURL: URL? = nil) async throws -> URL {
        return try await compressVideoToTargetSize(sourceURL: sourceURL, targetMB: 50.0, destinationURL: destinationURL)
    }
    
    /// Konvertiert in animiertes GIF (15 FPS)
    public func convertToAnimatedGIF(
        sourceURL: URL,
        destinationURL: URL? = nil,
        fps: Int = 15,
        maxDurationSeconds: Double = 12.0
    ) async throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let dest = destinationURL ?? safeDestination(for: sourceURL, newExtension: "gif")
        let asset = AVURLAsset(url: sourceURL)
        
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let effectiveDuration = min(totalSeconds, maxDurationSeconds)
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let frameInterval = 1.0 / Double(fps)
        var timestamps: [CMTime] = []
        var currentTime = 0.0
        while currentTime < effectiveDuration {
            timestamps.append(CMTime(seconds: currentTime, preferredTimescale: 600))
            currentTime += frameInterval
        }
        
        guard !timestamps.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: dest)
        }
        
        guard let destination = CGImageDestinationCreateWithURL(
            dest as CFURL,
            "com.compuserve.gif" as CFString,
            timestamps.count,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: frameInterval]
        ]
        
        for time in timestamps {
            if let (cgImage, _) = try? await imageGenerator.image(at: time) {
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            }
        }
        
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return dest
    }
    
    /// Audio-Extraktion als M4A/AAC
    public func extractAudio(sourceURL: URL, destinationURL: URL? = nil) async throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let dest = destinationURL ?? safeDestination(for: sourceURL, newExtension: "m4a")
        let asset = AVURLAsset(url: sourceURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        exportSession.outputURL = dest
        exportSession.outputFileType = .m4a
        
        if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: dest)
        }
        
        await exportSession.export()
        if exportSession.status == .completed {
            return dest
        } else {
            throw exportSession.error ?? CocoaError(.fileWriteUnknown)
        }
    }
    
    // MARK: - Bild Studio (Zuschneiden, Skalieren & Komprimieren)
    
    /// Seitenverhältnis-Crop (1:1 Quadrat, 16:9 Querformat, 9:16 Story/Reels)
    public func cropImage(
        sourceURL: URL,
        aspectRatio: AspectRatioPreset,
        destinationURL: URL? = nil
    ) throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let uti = CGImageSourceGetType(source) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        
        let targetRatio: CGFloat
        switch aspectRatio {
        case .square: targetRatio = 1.0
        case .landscape16_9: targetRatio = 16.0 / 9.0
        case .portrait9_16: targetRatio = 9.0 / 16.0
        }
        
        let cropWidth: CGFloat
        let cropHeight: CGFloat
        if (w / h) > targetRatio {
            cropHeight = h
            cropWidth = h * targetRatio
        } else {
            cropWidth = w
            cropHeight = w / targetRatio
        }
        
        let cropX = (w - cropWidth) / 2.0
        let cropY = (h - cropHeight) / 2.0
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let ext = sourceURL.pathExtension
        let ratioTag = aspectRatio.rawValue.replacingOccurrences(of: ":", with: "-")
        let dest = destinationURL ?? safeDestination(for: sourceURL, suffix: "Crop_\(ratioTag)", newExtension: ext)
        
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, uti, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, croppedCGImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return dest
    }
    
    /// Skalierung (z.B. scale = 0.5 für 50% Verkleinern, oder maxWidth = 1920)
    public func resizeImage(
        sourceURL: URL,
        scale: Double? = nil,
        maxWidth: CGFloat? = nil,
        destinationURL: URL? = nil
    ) throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let uti = CGImageSourceGetType(source) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let origW = CGFloat(cgImage.width)
        let origH = CGFloat(cgImage.height)
        
        let targetW: CGFloat
        let targetH: CGFloat
        if let maxW = maxWidth, origW > maxW {
            targetW = maxW
            targetH = origH * (maxW / origW)
        } else if let s = scale {
            targetW = origW * CGFloat(s)
            targetH = origH * CGFloat(s)
        } else {
            return sourceURL
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let targetWidthInt = max(1, Int(targetW))
        let targetHeightInt = max(1, Int(targetH))
        
        guard let context = CGContext(
            data: nil,
            width: targetWidthInt,
            height: targetHeightInt,
            bitsPerComponent: 8,
            bytesPerRow: targetWidthInt * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        
        guard let resizedCGImage = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let ext = sourceURL.pathExtension
        let tag = (scale != nil) ? "Scale50" : "Max1920"
        let dest = destinationURL ?? safeDestination(for: sourceURL, suffix: tag, newExtension: ext)
        
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, uti, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, resizedCGImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return dest
    }
    
    /// Kompression: 'Web-Optimiert' (80% Qualität) vs 'Verlustfrei'
    public func compressImage(
        sourceURL: URL,
        quality: Double,
        targetFormat: ImageTargetFormat? = nil,
        destinationURL: URL? = nil
    ) async throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let format = targetFormat ?? (quality < 0.99 ? .jpeg : .png)
        let qTag = Int(quality * 100)
        let dest = destinationURL ?? safeDestination(for: sourceURL, suffix: "Q\(qTag)", newExtension: format.rawValue)
        
        if format == .webp {
            return try await ConversionEngine.shared.convertToWebP(sourceURL: sourceURL, destinationURL: dest)
        }
        
        let uti: CFString = (format == .png) ? ("public.png" as CFString) : ("public.jpeg" as CFString)
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, uti, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return dest
    }
    
    /// Standard Bild-Konvertierung (PNG, JPEG, HEIC, WebP)
    public func convertImage(
        sourceURL: URL,
        targetFormat: ImageTargetFormat,
        destinationURL: URL? = nil
    ) async throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let dest = destinationURL ?? safeDestination(for: sourceURL, newExtension: targetFormat.rawValue)
        
        if targetFormat == .webp {
            return try await ConversionEngine.shared.convertToWebP(sourceURL: sourceURL, destinationURL: dest)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-s", "format", targetFormat.rawValue, sourceURL.path, "--out", dest.path]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 && FileManager.default.fileExists(atPath: dest.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return dest
    }
    
    /// Beliebiges Zielformat konvertieren / exportieren
    public func convertToCustomFormat(
        sourceURL: URL,
        targetExtension: String,
        destinationURL: URL? = nil
    ) async throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let cleanExt = targetExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        guard !cleanExt.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let dest = destinationURL ?? safeDestination(for: sourceURL, newExtension: cleanExt)
        
        if isImage(url: sourceURL) {
            if cleanExt == "webp" {
                return try await ConversionEngine.shared.convertToWebP(sourceURL: sourceURL, destinationURL: dest)
            }
            if ["png", "jpeg", "jpg", "heic", "tiff", "bmp", "icns", "pdf"].contains(cleanExt) {
                let sipsFormat = (cleanExt == "jpg") ? "jpeg" : cleanExt
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                process.arguments = ["-s", "format", sipsFormat, sourceURL.path, "--out", dest.path]
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: dest.path) {
                    return dest
                }
            }
        }
        
        if isVideo(url: sourceURL) {
            if cleanExt == "mp4" {
                return try await convertToWebMP4(sourceURL: sourceURL, destinationURL: dest)
            }
            if cleanExt == "gif" {
                return try await convertToAnimatedGIF(sourceURL: sourceURL, destinationURL: dest)
            }
            if cleanExt == "m4a" {
                return try await extractAudio(sourceURL: sourceURL, destinationURL: dest)
            }
        }
        
        if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest
    }
    
    // MARK: - Helpers
    
    public func isVideo(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let videoExtensions = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
        if videoExtensions.contains(ext) { return true }
        if let utType = UTType(filenameExtension: ext), utType.conforms(to: .movie) { return true }
        return false
    }
    
    public func isImage(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif", "bmp", "ico", "icns"]
        if imageExtensions.contains(ext) { return true }
        if let utType = UTType(filenameExtension: ext), utType.conforms(to: .image) { return true }
        return false
    }
    
    // MARK: - PDF Studio (Kompression & Extraktion)
    
    /// Echte PDF-Kompression: Rendert jede Seite auf maxDPI und komprimiert sie via JPEG
    public func compressPDF(
        sourceURL: URL,
        maxDPI: CGFloat = 150,
        quality: CGFloat = 0.65,
        destinationURL: URL? = nil
    ) throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let document = PDFDocument(url: sourceURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let newDocument = PDFDocument()
        let scale = maxDPI / 72.0
        
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            
            let pixelWidth = max(1, Int(pageBounds.width * scale))
            let pixelHeight = max(1, Int(pageBounds.height * scale))
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            
            // Weißer Hintergrund
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            
            // Skalierung für DPI
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            page.draw(with: .mediaBox, to: context)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            
            guard let cgImage = context.makeImage() else { continue }
            
            // JPEG-Kompression
            let jpegData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                jpegData as CFMutableData,
                "public.jpeg" as CFString,
                1,
                nil
            ) else { continue }
            
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { continue }
            
            if let compressedImage = NSImage(data: jpegData as Data),
               let newPage = PDFPage(image: compressedImage) {
                newPage.setBounds(pageBounds, for: .mediaBox)
                newDocument.insert(newPage, at: newDocument.pageCount)
            }
        }
        
        guard newDocument.pageCount > 0, let outputData = newDocument.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let dpiTag = (maxDPI <= 72) ? "Mail_72DPI" : "\(Int(maxDPI))DPI"
        let dest = destinationURL ?? safeDestination(for: sourceURL, suffix: "Compressed_\(dpiTag)", newExtension: "pdf")
        
        try outputData.write(to: dest, options: .atomic)
        return dest
    }
    
    /// Extrahiert Seiten aus einem PDF anhand eines Selektions-Strings wie "1, 3-5, 7"
    public func extractPages(
        sourceURL: URL,
        pageSelection: String,
        destinationURL: URL? = nil
    ) throws -> URL {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let document = PDFDocument(url: sourceURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let totalPages = document.pageCount
        guard totalPages > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let selectedIndices = parsePageSelection(pageSelection, totalPages: totalPages)
        guard !selectedIndices.isEmpty else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        
        let newDocument = PDFDocument()
        for idx in selectedIndices {
            if let page = document.page(at: idx) {
                newDocument.insert(page, at: newDocument.pageCount)
            }
        }
        
        guard newDocument.pageCount > 0, let outputData = newDocument.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let sanitizedSelection = pageSelection
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "_")
        let dest = destinationURL ?? safeDestination(for: sourceURL, suffix: "Pages_\(sanitizedSelection)", newExtension: "pdf")
        
        try outputData.write(to: dest, options: .atomic)
        return dest
    }
    
    /// 1-Klick Extraktion der ersten Seite (Titelseite / Deckblatt / Rechnung)
    public func extractFirstPage(
        sourceURL: URL,
        destinationURL: URL? = nil
    ) throws -> URL {
        return try extractPages(sourceURL: sourceURL, pageSelection: "1", destinationURL: destinationURL)
    }
    
    /// Hilfsfunktion: Parst Strings wie "1, 3-5, 7" in 0-basierte Seitenindizes
    public func parsePageSelection(_ input: String, totalPages: Int) -> [Int] {
        var pageNumbers = Set<Int>()
        let parts = input.components(separatedBy: ",")
        
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("-") {
                let rangeParts = trimmed.components(separatedBy: "-")
                if rangeParts.count == 2,
                   let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
                   let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)),
                   start <= end {
                    for p in start...end {
                        if p >= 1 && p <= totalPages {
                            pageNumbers.insert(p)
                        }
                    }
                }
            } else if let singlePage = Int(trimmed) {
                if singlePage >= 1 && singlePage <= totalPages {
                    pageNumbers.insert(singlePage)
                }
            }
        }
        
        return pageNumbers.sorted().map { $0 - 1 }
    }
    
    public func isPDF(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return true }
        if let utType = UTType(filenameExtension: ext), utType.conforms(to: .pdf) { return true }
        return false
    }
}
