import AppKit
import SwiftUI
import LedgeCore
import LedgeUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("=== DropLedge All-in-One Media Suite Initializing ===")
        
        // 1. Menüleisten-Dashboard einrichten
        MenuBarController.shared.setup()
        print("[DropLedge] MenuBarController active with tray.and.arrow.down symbol.")
        
        // 2. Clipboard Monitor aktivieren
        ClipboardMonitor.shared.onClipboardChanged = { pasteboard in
            let types = pasteboard.types?.map { $0.rawValue }.joined(separator: ", ") ?? "none"
            print("[DropLedge ClipboardMonitor] Detected pasteboard update. Types: \(types)")
        }
        ClipboardMonitor.shared.startMonitoring()
        print("[DropLedge] ClipboardMonitor active.")
        
        // 3. Screenshot Studio Callback: Popover öffnen & Vorschau zeigen
        ScreenshotStudio.shared.onScreenshotCaptured = { captured in
            print("[DropLedge] Screenshot captured! Length: \(captured.ocrText.count) chars OCR.")
            MenuBarController.shared.showPopover()
        }
        
        // 4. Globale Hotkeys registrieren:
        //    Cmd + Option + S -> Quick-Save
        //    Cmd + Shift + D  -> Toggle Popover
        //    Cmd + Shift + X  -> Screenshot & Extract
        GlobalHotkeyManager.shared.onQuickSaveTriggered = {
            Task { @MainActor in
                print("[DropLedge] Quick-Save Hotkey (Cmd + Option + S) triggered!")
                do {
                    let baseDir = AppState.shared.libraryDirectory
                    if let savedURL = try await LedgeCoordinator.shared.quickSaveClipboard(baseDirectory: baseDir) {
                        HapticAudioEngine.shared.play(.dropSuccess)
                        print("[DropLedge] Quick-Saved clipboard item to: \(savedURL.path)")
                    } else {
                        print("[DropLedge] Clipboard was empty or contained no recognizable data.")
                    }
                } catch {
                    print("[DropLedge] Quick-Save error: \(error)")
                }
            }
        }
        
        GlobalHotkeyManager.shared.onTogglePopoverTriggered = {
            Task { @MainActor in
                print("[DropLedge] Toggle Popover Hotkey (Cmd + Shift + D) triggered!")
                MenuBarController.shared.togglePopover()
            }
        }
        
        GlobalHotkeyManager.shared.onScreenshotTriggered = {
            Task { @MainActor in
                print("[DropLedge] Screenshot & Extract Hotkey (Cmd + Shift + X) triggered!")
                ScreenshotStudio.shared.captureInteractiveScreenshot()
            }
        }
        
        GlobalHotkeyManager.shared.registerHotkeys()
        print("[DropLedge] Global Hotkeys registered: Cmd+Option+S (Save), Cmd+Shift+D (Popover), Cmd+Shift+X (Capture).")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stopMonitoring()
        GlobalHotkeyManager.shared.unregister()
        print("[DropLedge] Terminated cleanly.")
    }
}
