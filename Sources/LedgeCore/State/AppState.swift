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
        recentItems.removeAll {
            $0.id == item.id ||
            ($0.fileURL != nil && item.fileURL != nil && $0.fileURL == item.fileURL) ||
            ($0.originalURL != nil && item.originalURL != nil && $0.originalURL == item.originalURL)
        }
        recentItems.insert(item, at: 0)
        self.selectedOrLastDroppedItem = item
    }
    
    public func removeItem(_ item: LedgeItem, moveToTrash: Bool = true) {
        recentItems.removeAll { $0.id == item.id }
        scratchpadItems.removeAll { $0.id == item.id }
        if selectedOrLastDroppedItem?.id == item.id {
            selectedOrLastDroppedItem = recentItems.first
        }
        
        guard moveToTrash else { return }
        
        // SICHERHEITS-SCHUTZ: Externe Original-Dateien des Nutzers NIEMALS vom Dateisystem löschen!
        guard let savedURL = item.savedURL else {
            // Reines Shelf-Item einer Originaldatei -> Nur aus der Liste entfernen, niemals anfassen!
            return
        }
        
        // Falls savedURL und originalURL auf dieselbe Datei verweisen: Niemals löschen!
        if let original = item.originalURL, original.standardizedFileURL.path == savedURL.standardizedFileURL.path {
            return
        }
        
        // Nur von DropLedge intern generierte Dateien (in DropLedge Library oder NSTemporaryDirectory) dürfen in den Papierkorb:
        let libPath = libraryDirectory.standardizedFileURL.path
        let tempPath = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
        let filePath = savedURL.standardizedFileURL.path
        
        if filePath.hasPrefix(libPath) || filePath.hasPrefix(tempPath) {
            if FileManager.default.fileExists(atPath: filePath) {
                try? FileManager.default.trashItem(at: savedURL, resultingItemURL: nil)
            }
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
        
        // 1. Für jede abgelegte Datei genau EINEN Shelf-Eintrag anlegen mit originalURL
        // savedURL bleibt nil, da die Datei extern auf dem Mac des Nutzers liegt und nicht dupliziert wird.
        for url in urls {
            let item = LedgeItem(
                originalURL: url,
                savedURL: nil,
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
            
            // 2. OCR im Hintergrund für Bilddateien ausführen und denselben Eintrag aktualisieren
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
                    if let ocr = try? await coordinator.extractOCRText(from: url) {
                        await MainActor.run {
                            if let idx = self.recentItems.firstIndex(where: { $0.originalURL == url || $0.fileURL == url }) {
                                var existing = self.recentItems[idx]
                                existing.extractedText = ocr
                                self.recentItems[idx] = existing
                                if self.selectedOrLastDroppedItem?.id == existing.id {
                                    self.selectedOrLastDroppedItem = existing
                                }
                            }
                        }
                    }
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
