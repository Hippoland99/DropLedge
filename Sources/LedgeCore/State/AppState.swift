import SwiftUI
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
public final class AppState {
    public static let shared = AppState()
    
    public var isPanelVisible: Bool = false
    public var isDraggingOver: Bool = false
    public var activeZone: DropZoneType?
    
    public var recentItems: [LedgeItem] = []
    public var scratchpadItems: [LedgeItem] = []
    
    public var selectedOrLastDroppedItem: LedgeItem?
    public var capturedScreenshot: CapturedScreenshot?
    
    // Pin-Funktion für Menüleisten-Popover
    public var isPinned: Bool = false
    
    // Konvertierungs-Status
    public var isConverting: Bool = false
    public var conversionStatusMessage: String?
    
    public var libraryDirectory: URL
    public var lastActionDescription: String?
    public var statusToastMessage: String?
    
    /// Die letzten 4 gespeicherten Dateien für das Scratchpad
    public var lastFourSavedItems: [LedgeItem] {
        Array(recentItems.prefix(4))
    }
    
    public init() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        self.libraryDirectory = documentsURL.appendingPathComponent("DropLedge Library", isDirectory: true)
    }
    
    public func addOrUpdateItem(_ item: LedgeItem) {
        recentItems.removeAll { $0.id == item.id || ($0.fileURL != nil && $0.fileURL == item.fileURL) }
        recentItems.insert(item, at: 0)
        self.selectedOrLastDroppedItem = item
    }
    
    public func removeItem(_ item: LedgeItem, moveToTrash: Bool = true) {
        recentItems.removeAll { $0.id == item.id }
        scratchpadItems.removeAll { $0.id == item.id }
        if selectedOrLastDroppedItem?.id == item.id {
            selectedOrLastDroppedItem = recentItems.first
        }
        
        if moveToTrash, let url = item.fileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }
    
    /// Erstellt eine Datei für das Text & Code Snippet Studio und fügt sie sofort ins Scratchpad ein
    public func createSnippetFile(
        text: String,
        fileName: String,
        fileExtension: String
    ) async throws -> URL {
        let coordinator = LedgeCoordinator.shared
        let savedURL = try await coordinator.saveSnippet(
            text: text,
            fileName: fileName,
            fileExtension: fileExtension,
            baseDirectory: self.libraryDirectory
        )
        
        let item = LedgeItem(
            originalURL: nil,
            savedURL: savedURL,
            timestamp: Date(),
            contentType: UTType(filenameExtension: savedURL.pathExtension) ?? .plainText,
            suggestedFileName: savedURL.lastPathComponent,
            extractedText: text,
            tags: ["Snippet", fileExtension]
        )
        
        self.addOrUpdateItem(item)
        return savedURL
    }
    
    public func handleDrop(in zone: DropZoneType, urls: [URL], text: String?) {
        self.lastActionDescription = "Dropped \(urls.count) items into \(zone.rawValue)"
        
        for url in urls {
            let item = LedgeItem(
                originalURL: url,
                savedURL: url,
                timestamp: Date(),
                contentType: UTType(filenameExtension: url.pathExtension) ?? .item,
                suggestedFileName: url.lastPathComponent,
                extractedText: nil,
                tags: [zone.rawValue]
            )
            addOrUpdateItem(item)
        }
        
        if let text = text, !text.isEmpty {
            let item = LedgeItem(
                originalURL: nil,
                savedURL: nil,
                timestamp: Date(),
                contentType: .plainText,
                suggestedFileName: "Snippet.txt",
                extractedText: text,
                tags: [zone.rawValue, "Text"]
            )
            addOrUpdateItem(item)
        }
        
        Task {
            let coordinator = LedgeCoordinator.shared
            let baseDir = self.libraryDirectory
            
            for url in urls {
                do {
                    let saved = try await coordinator.processDroppedFileURL(url, baseDirectory: baseDir)
                    var updated = LedgeItem(
                        originalURL: url,
                        savedURL: saved,
                        timestamp: Date(),
                        contentType: UTType(filenameExtension: saved.pathExtension) ?? .item,
                        suggestedFileName: saved.lastPathComponent,
                        extractedText: nil,
                        tags: [zone.rawValue]
                    )
                    if ["png", "jpg", "jpeg", "heic", "webp"].contains(saved.pathExtension.lowercased()) {
                        if let ocr = try? await coordinator.extractOCRText(from: saved) {
                            updated.extractedText = ocr
                        }
                    }
                    self.addOrUpdateItem(updated)
                } catch {
                    print("[DropLedge] Error saving dropped file: \(error)")
                }
            }
            
            if let text = text, !text.isEmpty {
                do {
                    let saved = try await coordinator.processDroppedText(text, baseDirectory: baseDir)
                    let updated = LedgeItem(
                        originalURL: nil,
                        savedURL: saved,
                        timestamp: Date(),
                        contentType: .plainText,
                        suggestedFileName: saved.lastPathComponent,
                        extractedText: text,
                        tags: [zone.rawValue, "Text"]
                    )
                    self.addOrUpdateItem(updated)
                } catch {
                    print("[DropLedge] Error saving dropped text: \(error)")
                }
            }
        }
    }
}
