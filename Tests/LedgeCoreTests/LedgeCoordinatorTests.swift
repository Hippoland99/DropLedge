import XCTest
import AppKit
import CoreGraphics
import ImageIO
@testable import LedgeCore
@testable import StorageCoordinator

final class LedgeCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LedgeCoordinatorTests_\(uniqueID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }
    
    private func createTestPNGData(text: String) -> Data {
        let width = 450
        let height = 100
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
        
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        
        let font = NSFont.boldSystemFont(ofSize: 32)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let nsText = text as NSString
        nsText.draw(at: NSPoint(x: 20, y: 30), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        
        let cgImage = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }
    
    func testProcessDroppedCodeText() async throws {
        let coordinator = LedgeCoordinator.shared
        let swiftCode = """
        import SwiftUI
        
        struct QuickView: View {
            var body: some View {
                Text("Swift Pipeline")
            }
        }
        """
        
        let savedURL = try await coordinator.processDroppedText(swiftCode, baseDirectory: tempDirectory, sourceApp: "Xcode")
        
        // Verifiziere Endung, Ordner und Inhalt
        XCTAssertEqual(savedURL.pathExtension, "swift")
        XCTAssertTrue(savedURL.path.contains("Code"))
        let content = try String(contentsOf: savedURL, encoding: .utf8)
        XCTAssertTrue(content.contains("QuickView"))
        
        // Verifiziere Finder Comment
        let comment = try await StorageCoordinator.shared.getFinderComment(for: savedURL)
        XCTAssertEqual(comment, swiftCode)
    }
    
    func testProcessDroppedImageWithOCR() async throws {
        let coordinator = LedgeCoordinator.shared
        let testImagePNG = createTestPNGData(text: "DropLedge OCR Pipeline")
        
        let result = try await coordinator.processDroppedImage(
            data: testImagePNG,
            fileExtension: "png",
            baseDirectory: tempDirectory,
            sourceApp: "ScreenCapture"
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.savedURL.path(percentEncoded: false)))
        XCTAssertTrue(result.savedURL.path.contains("Media"))
        XCTAssertNotNil(result.ocrText)
        XCTAssertTrue(result.ocrText?.contains("DropLedge") ?? false)
        
        // Verifiziere Finder Comment mit OCR-Text
        let comment = try await StorageCoordinator.shared.getFinderComment(for: result.savedURL)
        XCTAssertEqual(comment, result.ocrText)
    }
    
    @MainActor
    func testClipboardMonitorDetectsChanges() {
        let monitor = ClipboardMonitor.shared
        var detectedChange = false
        
        monitor.onClipboardChanged = { _ in
            detectedChange = true
        }
        
        // Schreibe neuen String ins Pasteboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("Unit-Test Clipboard Item", forType: .string)
        
        monitor.checkForChanges()
        XCTAssertTrue(detectedChange)
    }
    
    func testSaveSnippetAndCategory() async throws {
        let coordinator = LedgeCoordinator.shared
        let pySnippet = "def calculate_sum(a, b):\n    return a + b"
        let savedPy = try await coordinator.saveSnippet(
            text: pySnippet,
            fileName: "MySnippet",
            fileExtension: "py",
            baseDirectory: tempDirectory
        )
        
        XCTAssertEqual(savedPy.pathExtension, "py")
        XCTAssertEqual(savedPy.lastPathComponent, "MySnippet.py")
        XCTAssertTrue(savedPy.path.contains("Code"))
        let content = try String(contentsOf: savedPy, encoding: .utf8)
        XCTAssertEqual(content, pySnippet)
        
        // Text / ENV landet in RawText
        let envSnippet = "PORT=3000\nHOST=127.0.0.1"
        let savedEnv = try await coordinator.saveSnippet(
            text: envSnippet,
            fileName: "LocalEnv",
            fileExtension: "env",
            baseDirectory: tempDirectory
        )
        XCTAssertEqual(savedEnv.pathExtension, "env")
        XCTAssertTrue(savedEnv.path.contains("RawText"))
    }
    
    func testLedgeItemSizeSavingsCalculation() throws {
        let dummyURL = tempDirectory.appendingPathComponent("test.pdf")
        let smallData = Data(repeating: 0x41, count: 180_000) // 180 KB
        try smallData.write(to: dummyURL)
        
        let itemWithSavings = LedgeItem(
            originalURL: nil,
            savedURL: dummyURL,
            contentType: .pdf,
            suggestedFileName: "test.pdf",
            originalSizeBytes: 1_000_000 // 1 MB original
        )
        
        XCTAssertTrue(itemWithSavings.hasSavings)
        XCTAssertNotNil(itemWithSavings.sizeSavingsBadge)
        XCTAssertTrue(itemWithSavings.sizeSavingsBadge?.contains("(-") ?? false)
        XCTAssertTrue(itemWithSavings.sizeSavingsBadge?.contains("%)") ?? false)
    }
    
    func testHapticAudioEnginePlaybackForAllEffects() {
        let engine = HapticAudioEngine.shared
        let effects: [SoundEffect] = [
            .dropSuccess,
            .conversionDone,
            .dragOut,
            .deleteItem,
            .screenshotTaken,
            .pinToggled
        ]
        
        for effect in effects {
            engine.play(effect)
        }
        
        // Wait briefly for main queue dispatch to complete cleanly without crash
        let exp = expectation(description: "Effects dispatched")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testQuickSaveClipboardWithPNGScreenshot() async throws {
        let coordinator = LedgeCoordinator.shared
        let pngData = createTestPNGData(text: "Clipboard Screenshot OCR")
        
        // Simuliere Screenshot in NSPasteboard.general
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        
        let savedURL = try await coordinator.quickSaveClipboard(baseDirectory: tempDirectory)
        XCTAssertNotNil(savedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL!.path))
        XCTAssertEqual(savedURL?.pathExtension.lowercased(), "png")
    }
    
    func testQuickSaveClipboardWithCopiedFileURL() async throws {
        let coordinator = LedgeCoordinator.shared
        let dummyFileURL = tempDirectory.appendingPathComponent("finder_copied_\(UUID().uuidString).json")
        try "{\"status\":\"ok\"}".write(to: dummyFileURL, atomically: true, encoding: .utf8)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([dummyFileURL as NSURL])
        
        let savedURL = try await coordinator.quickSaveClipboard(baseDirectory: tempDirectory)
        XCTAssertNotNil(savedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL!.path))
        XCTAssertEqual(savedURL?.pathExtension.lowercased(), "json")
    }
}
