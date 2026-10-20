import AppKit
import Foundation
import VisionEngine
import StorageCoordinator

public struct CapturedScreenshot: Sendable, Identifiable {
    public let id: UUID
    public let fileURL: URL
    public let ocrText: String
    public let timestamp: Date
    
    public init(id: UUID = UUID(), fileURL: URL, ocrText: String, timestamp: Date = Date()) {
        self.id = id
        self.fileURL = fileURL
        self.ocrText = ocrText
        self.timestamp = timestamp
    }
}

@MainActor
public final class ScreenshotStudio {
    public static let shared = ScreenshotStudio()
    
    public var onScreenshotCaptured: ((CapturedScreenshot) -> Void)?
    
    private init() {}
    
    /// Startet die interaktive Bildschirmerfassung via /usr/sbin/screencapture -i -c
    public func captureInteractiveScreenshot() {
        Task.detached {
            let initialChangeCount = await MainActor.run { NSPasteboard.general.changeCount }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c"]
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("[DropLedge ScreenshotStudio] Process Error: \(error)")
                return
            }
            
            // Wenn der Nutzer mit Escape abgebrochen hat, keine Änderung
            let currentChangeCount = await MainActor.run { NSPasteboard.general.changeCount }
            guard currentChangeCount > initialChangeCount else {
                print("[DropLedge ScreenshotStudio] Capture abgebrochen (Escape gedrückt).")
                return
            }
            
            // Lese Bild aus Pasteboard
            await MainActor.run {
                guard let image = NSImage(pasteboard: .general),
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    return
                }
                
                let isoFormatter = ISO8601DateFormatter()
                let timestamp = isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let tempFileURL = tempDir.appendingPathComponent("DropLedge_Capture_\(timestamp).png")
                
                do {
                    try pngData.write(to: tempFileURL, options: .atomic)
                } catch {
                    print("[DropLedge ScreenshotStudio] Fehler beim Schreiben des Temp-Screenshots: \(error)")
                    return
                }
                
                Task {
                    var ocrText = ""
                    do {
                        let result = try await VisionEngine.shared.recognizeText(from: pngData)
                        ocrText = result.fullText
                    } catch {
                        ocrText = ""
                    }
                    
                    let captured = CapturedScreenshot(
                        fileURL: tempFileURL,
                        ocrText: ocrText
                    )
                    
                    let item = LedgeItem(
                        originalURL: tempFileURL,
                        savedURL: tempFileURL,
                        timestamp: Date(),
                        contentType: .image,
                        suggestedFileName: tempFileURL.lastPathComponent,
                        extractedText: ocrText.isEmpty ? nil : ocrText,
                        tags: ["Screenshot", "OCR"]
                    )
                    
                    AppState.shared.capturedScreenshot = captured
                    AppState.shared.addOrUpdateItem(item)
                    ScreenshotStudio.shared.onScreenshotCaptured?(captured)
                    HapticAudioEngine.shared.play(.screenshotTaken)
                }
            }
        }
    }
}
