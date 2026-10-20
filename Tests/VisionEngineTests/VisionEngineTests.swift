import XCTest
import AppKit
import CoreGraphics
import ImageIO
@testable import VisionEngine

final class VisionEngineTests: XCTestCase {
    
    private func createTextImage(text: String, size: CGSize = CGSize(width: 500, height: 120)) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Konnte CGContext nicht initialisieren")
        }
        
        // Weisser Hintergrund
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Text zeichnen
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        
        let font = NSFont.boldSystemFont(ofSize: 32)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let nsText = text as NSString
        nsText.draw(at: NSPoint(x: 20, y: 35), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        
        return context.makeImage()!
    }
    
    private func createEmptyImage(size: CGSize = CGSize(width: 200, height: 200)) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
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
        return context.makeImage()!
    }
    
    func testOCRRecognizesCrispText() async throws {
        let engine = VisionEngine.shared
        let expectedPhrase = "DropLedge OCR Test"
        let testImage = createTextImage(text: expectedPhrase)
        
        let result = try await engine.recognizeText(from: testImage, languages: ["en-US"])
        
        XCTAssertTrue(result.fullText.contains("DropLedge"))
        XCTAssertTrue(result.fullText.contains("OCR"))
        XCTAssertGreaterThanOrEqual(result.confidence, 0.5)
        XCTAssertGreaterThan(result.lineCount, 0)
    }
    
    func testEmptyImageThrowsNoTextDetected() async {
        let engine = VisionEngine.shared
        let emptyImage = createEmptyImage()
        
        do {
            _ = try await engine.recognizeText(from: emptyImage, languages: ["en-US"])
            XCTFail("Erwarteter Fehler noTextDetected wurde nicht geworfen")
        } catch let error as VisionEngine.VisionError {
            XCTAssertEqual(error, .noTextDetected)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
    }
    
    func testRecognizeFromPNGImageData() async throws {
        let engine = VisionEngine.shared
        let testImage = createTextImage(text: "Native Apple Neural Engine")
        
        let pngData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(pngData as CFMutableData, "public.png" as CFString, 1, nil) else {
            XCTFail("Konnte CGImageDestination nicht erstellen")
            return
        }
        CGImageDestinationAddImage(destination, testImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        
        let result = try await engine.recognizeText(from: pngData as Data, languages: ["en-US"])
        XCTAssertTrue(result.fullText.contains("Neural Engine"))
    }
}
