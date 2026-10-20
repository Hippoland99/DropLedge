import XCTest
import CoreGraphics
import ImageIO
import AppKit
import PDFKit
@testable import ConversionEngine

final class OmniConverterEngineTests: XCTestCase {
    private var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OmniConverterTests_\(uniqueID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }
    
    private func createTestImageFile(named name: String = "sample.png") throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = context.makeImage()!
        
        let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return fileURL
    }
    
    private func createTestPDFFile(named name: String = "sample.pdf", pages: Int = 3) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        let pdfDoc = PDFDocument()
        for i in 1...pages {
            let width = 200
            let height = 300
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(red: CGFloat(i) / CGFloat(pages), green: 0.5, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let img = context.makeImage()!
            let nsImg = NSImage(cgImage: img, size: NSSize(width: width, height: height))
            if let page = PDFPage(image: nsImg) {
                pdfDoc.insert(page, at: pdfDoc.pageCount)
            }
        }
        guard let data = pdfDoc.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: fileURL)
        return fileURL
    }
    
    func testImageConversionToJPEGAndHEIC() async throws {
        let engine = OmniConverterEngine.shared
        let sourceURL = try createTestImageFile(named: "source.png")
        
        // 1. Zu JPEG konvertieren
        let jpegURL = try await engine.convertImage(sourceURL: sourceURL, targetFormat: .jpeg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpegURL.path))
        XCTAssertEqual(jpegURL.pathExtension, "jpeg")
        
        // 2. Zu HEIC konvertieren
        let heicURL = try await engine.convertImage(sourceURL: sourceURL, targetFormat: .heic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: heicURL.path))
        XCTAssertEqual(heicURL.pathExtension, "heic")
    }
    
    func testCropImageSquareAndLandscape() async throws {
        let engine = OmniConverterEngine.shared
        let sourceURL = try createTestImageFile(named: "to_crop.png")
        
        let croppedSquare = try await engine.cropImage(sourceURL: sourceURL, aspectRatio: .square)
        XCTAssertTrue(FileManager.default.fileExists(atPath: croppedSquare.path))
        
        let croppedLandscape = try await engine.cropImage(sourceURL: sourceURL, aspectRatio: .landscape16_9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: croppedLandscape.path))
    }
    
    func testResizeImageScaleAndMaxWidth() async throws {
        let engine = OmniConverterEngine.shared
        let sourceURL = try createTestImageFile(named: "to_resize.png")
        
        let resizedHalf = try await engine.resizeImage(sourceURL: sourceURL, scale: 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resizedHalf.path))
        
        let resizedMax = try await engine.resizeImage(sourceURL: sourceURL, maxWidth: 32)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resizedMax.path))
    }
    
    func testCompressImageQuality() async throws {
        let engine = OmniConverterEngine.shared
        let sourceURL = try createTestImageFile(named: "to_compress.png")
        
        let compressed = try await engine.compressImage(sourceURL: sourceURL, quality: 0.8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: compressed.path))
    }
    
    func testMediaTypeDetection() async {
        let engine = OmniConverterEngine.shared
        
        let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
        let imageURL = URL(fileURLWithPath: "/tmp/photo.heic")
        let codeURL = URL(fileURLWithPath: "/tmp/main.swift")
        
        let isVideo = await engine.isVideo(url: videoURL)
        let isImage = await engine.isImage(url: imageURL)
        let isCodeVideo = await engine.isVideo(url: codeURL)
        let isPDF = await engine.isPDF(url: URL(fileURLWithPath: "/tmp/doc.pdf"))
        
        XCTAssertTrue(isVideo)
        XCTAssertTrue(isImage)
        XCTAssertFalse(isCodeVideo)
        XCTAssertTrue(isPDF)
    }
    
    func testPDFCompression() async throws {
        let engine = OmniConverterEngine.shared
        let sourceURL = try createTestPDFFile(named: "to_compress.pdf", pages: 3)
        
        let compressedURL = try await engine.compressPDF(sourceURL: sourceURL, maxDPI: 72, quality: 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: compressedURL.path))
        XCTAssertEqual(compressedURL.pathExtension, "pdf")
        
        let doc = PDFDocument(url: compressedURL)
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc?.pageCount, 3)
    }
    
    func testPDFPageSelectionParsing() async {
        let engine = OmniConverterEngine.shared
        
        let indices = await engine.parsePageSelection("1, 3-5, 7", totalPages: 10)
        XCTAssertEqual(indices, [0, 2, 3, 4, 6])
        
        let indicesSingle = await engine.parsePageSelection("2", totalPages: 5)
        XCTAssertEqual(indicesSingle, [1])
        
        let indicesOutOfBounds = await engine.parsePageSelection("99", totalPages: 5)
        XCTAssertTrue(indicesOutOfBounds.isEmpty)
    }
    
    func testPDFExtractPages() async throws {
        let engine = OmniConverterEngine.shared
        let sourceURL = try createTestPDFFile(named: "multi_pages.pdf", pages: 4)
        
        let extractedURL = try await engine.extractPages(sourceURL: sourceURL, pageSelection: "1, 3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedURL.path))
        
        let doc = PDFDocument(url: extractedURL)
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc?.pageCount, 2)
    }
    
    func testPDFExtractFirstPage() async throws {
        let engine = OmniConverterEngine.shared
        let sourceURL = try createTestPDFFile(named: "invoice.pdf", pages: 3)
        
        let firstPageURL = try await engine.extractFirstPage(sourceURL: sourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstPageURL.path))
        
        let doc = PDFDocument(url: firstPageURL)
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc?.pageCount, 1)
    }
}
