import XCTest
import AppKit
import SwiftUI
import CodeAnalysis
@testable import LedgeCore
@testable import LedgeUI

final class LedgeUITests: XCTestCase {
    
    @MainActor
    func testMenuBarControllerSetup() {
        let controller = MenuBarController.shared
        controller.setup()
        
        // 1. StatusItem existiert und hat ein Icon
        XCTAssertNotNil(controller.statusItem)
        XCTAssertNotNil(controller.statusItem?.button)
        XCTAssertNotNil(controller.statusItem?.button?.image)
        
        // 2. Popover ist konfiguriert
        XCTAssertNotNil(controller.popover)
        XCTAssertEqual(controller.popover?.behavior, .transient)
        XCTAssertTrue(controller.popover?.contentViewController is NSHostingController<LedgePopoverView>)
    }
    
    @MainActor
    func testPinToggleChangesPopoverBehavior() {
        let controller = MenuBarController.shared
        controller.setup()
        
        // Default: transient
        XCTAssertEqual(controller.popover?.behavior, .transient)
        
        // Angepinnt: applicationDefined (schließt nicht bei Außen-Klick)
        controller.isPinned = true
        XCTAssertEqual(controller.popover?.behavior, .applicationDefined)
        
        // Nicht angepinnt: transient
        controller.isPinned = false
        XCTAssertEqual(controller.popover?.behavior, .transient)
    }
    
    @MainActor
    func testStatusItemDragDestinationRegistration() {
        let controller = MenuBarController.shared
        controller.setup()
        
        guard let button = controller.statusItem?.button else {
            XCTFail("Button auf statusItem fehlt")
            return
        }
        
        let overlay = button.subviews.first(where: { $0 is StatusItemDragOverlayView }) as? StatusItemDragOverlayView
        XCTAssertNotNil(overlay, "StatusItemDragOverlayView wurde nicht als Subview hinzugefügt")
        XCTAssertTrue(overlay?.registeredDraggedTypes.contains(.fileURL) ?? false)
    }
    
    @MainActor
    func testScratchpadAndItemDeletion() async throws {
        let appState = AppState.shared
        let dummyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("report_\(UUID().uuidString).pdf")
        try "dummy report content".data(using: .utf8)?.write(to: dummyURL)
        
        appState.handleDrop(in: .smartSave, urls: [dummyURL], text: nil)
        
        guard let firstItem = appState.lastFourSavedItems.first else {
            XCTFail("Item nicht hinzugefügt")
            return
        }
        
        // Dateiname erhalten (kein generic Name)
        XCTAssertEqual(firstItem.suggestedFileName, dummyURL.lastPathComponent)
        XCTAssertEqual(firstItem.fileURL?.lastPathComponent, dummyURL.lastPathComponent)
        
        // NSItemProvider mit suggestedName verifizieren
        let provider = NSItemProvider(contentsOf: firstItem.fileURL!)
        provider?.suggestedName = firstItem.fileURL!.lastPathComponent
        XCTAssertEqual(provider?.suggestedName, dummyURL.lastPathComponent)
        
        // Kurze Pause für Hintergrund-Task, dann Löschfunktion testen
        try await Task.sleep(nanoseconds: 150_000_000)
        appState.removeItem(firstItem, moveToTrash: true)
        XCTAssertFalse(appState.recentItems.contains(where: { $0.id == firstItem.id }))
        // Sicherheits-Check: Die Originaldatei darf NICHT gelöscht werden!
        XCTAssertTrue(FileManager.default.fileExists(atPath: dummyURL.path), "Original-Datei wurde fälschlicherweise gelöscht!")
    }
    
    func testSnippetDraftAndAutoDetection() {
        let jsonSample = "{\"api\": \"DropLedge\", \"active\": true}"
        let classification = CodeClassifier.classify(rawText: jsonSample)
        let draft = SnippetDraft(rawText: jsonSample, initialExtension: classification.fileExtension)
        
        XCTAssertEqual(draft.initialExtension, "json")
        XCTAssertEqual(draft.lineCount, 1)
        XCTAssertEqual(draft.previewLines.first, jsonSample)
    }
    
    @MainActor
    func testClipboardFilePasteHandling() throws {
        let appState = AppState.shared
        let dummyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pasted_doc_\(UUID().uuidString).txt")
        try "Test Paste Content".write(to: dummyURL, atomically: true, encoding: .utf8)
        
        // Simuliere Kopieren im Finder auf NSPasteboard.general
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([dummyURL as NSURL])
        
        // Verifiziere, dass NSPasteboard die Datei als URL enthält
        let readURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]
        ) as? [URL]
        
        XCTAssertNotNil(readURLs)
        XCTAssertFalse(readURLs?.isEmpty ?? true)
        XCTAssertEqual(readURLs?.first?.path, dummyURL.path)
        
        // Simuliere Drop / Paste ins AppState
        appState.handleDrop(in: .smartSave, urls: readURLs!, text: nil)
        XCTAssertTrue(appState.recentItems.contains(where: { $0.suggestedFileName == dummyURL.lastPathComponent }))
    }
    
    @MainActor
    func testDroppingFileDoesNotDuplicateOrDeleteOriginal() async throws {
        let appState = AppState.shared
        let originalURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cover_test_\(UUID().uuidString).jpg")
        let dummyBytes = Data(repeating: 0xFF, count: 512)
        try dummyBytes.write(to: originalURL, options: .atomic)
        
        let initialCount = appState.recentItems.count
        
        // 1. Datei droppen
        appState.handleDrop(in: .smartSave, urls: [originalURL], text: nil)
        
        // Es darf genau 1 Item mehr existieren
        XCTAssertEqual(appState.recentItems.count, initialCount + 1)
        
        // Warten auf Hintergrund-Task
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Es darf immer noch genau 1 Item mehr existieren (KEINE Duplikate / zweite Datei!)
        XCTAssertEqual(appState.recentItems.count, initialCount + 1)
        
        guard let item = appState.recentItems.first(where: { $0.originalURL == originalURL }) else {
            XCTFail("Item nicht gefunden")
            return
        }
        
        XCTAssertEqual(item.suggestedFileName, originalURL.lastPathComponent)
        XCTAssertNil(item.savedURL, "savedURL sollte für externe Originaldateien nil sein")
        
        // 2. Item aus Scratchpad löschen
        appState.removeItem(item, moveToTrash: true)
        
        // Item ist aus der UI entfernt
        XCTAssertFalse(appState.recentItems.contains(where: { $0.id == item.id }))
        
        // KRITISCH: Die Originaldatei auf der Festplatte MUSS intakt bleiben!
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path), "Originaldatei wurde gelöscht!")
        
        // Aufräumen
        try? FileManager.default.removeItem(at: originalURL)
    }
    
    func testUniversalDragOutProviderForWebsitesAndApps() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DropLedge_UniversalDrag_\(UUID().uuidString).png")
        try "test-content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let provider = makeFileItemProvider(for: tempURL)
        
        // 1. suggestedName MUSS mit Dateinamen übereinstimmen
        XCTAssertEqual(provider.suggestedName, tempURL.lastPathComponent)
        
        // 2. 'public.file-url' MUSS als allererste Registrierung vorhanden sein (damit Browser es als File erkennen)
        XCTAssertEqual(provider.registeredTypeIdentifiers.first, "public.file-url")
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains("public.url"))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains("public.png"))
        
        // 3. Kann als NSURL geladen werden
        XCTAssertTrue(provider.canLoadObject(ofClass: NSURL.self))
    }
}
