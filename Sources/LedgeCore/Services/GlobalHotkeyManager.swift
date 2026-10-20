import AppKit
import Carbon

@MainActor
public final class GlobalHotkeyManager {
    public static let shared = GlobalHotkeyManager()
    
    private var quickSaveHotKeyRef: EventHotKeyRef?
    private var togglePopoverHotKeyRef: EventHotKeyRef?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    
    public var onQuickSaveTriggered: (() -> Void)?
    public var onTogglePopoverTriggered: (() -> Void)?
    public var onScreenshotTriggered: (() -> Void)?
    
    private init() {}
    
    public func registerHotkeys() {
        // 1. Hotkey 1: Quick-Save (Cmd + Option + S) -> kVK_ANSI_S = 1
        let quickSaveID = EventHotKeyID(signature: OSType(0x44504C31), id: 1)
        let quickSaveMods = UInt32(cmdKey | optionKey)
        _ = RegisterEventHotKey(1, quickSaveMods, quickSaveID, GetApplicationEventTarget(), 0, &quickSaveHotKeyRef)
        
        // 2. Hotkey 2: Toggle Popover (Cmd + Shift + D) -> kVK_ANSI_D = 2
        let popoverID = EventHotKeyID(signature: OSType(0x44504C32), id: 2)
        let popoverMods = UInt32(cmdKey | shiftKey)
        _ = RegisterEventHotKey(2, popoverMods, popoverID, GetApplicationEventTarget(), 0, &togglePopoverHotKeyRef)
        
        // 3. Hotkey 3: Screenshot & Extract (Cmd + Shift + X) -> kVK_ANSI_X = 7
        let screenshotID = EventHotKeyID(signature: OSType(0x44504C33), id: 3)
        let screenshotMods = UInt32(cmdKey | shiftKey)
        _ = RegisterEventHotKey(7, screenshotMods, screenshotID, GetApplicationEventTarget(), 0, &screenshotHotKeyRef)
        
        // Carbon Event Handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if err == noErr {
                Task { @MainActor in
                    switch hotKeyID.id {
                    case 1:
                        GlobalHotkeyManager.shared.onQuickSaveTriggered?()
                    case 2:
                        GlobalHotkeyManager.shared.onTogglePopoverTriggered?()
                    case 3:
                        GlobalHotkeyManager.shared.onScreenshotTriggered?()
                    default:
                        break
                    }
                }
            }
            return noErr
        }, 1, &eventSpec, nil, &eventHandlerRef)
        
        // Lokaler Monitor (falls Popover/App aktiv)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags
            let char = event.charactersIgnoringModifiers?.lowercased()
            
            if mods.contains([.command, .option]) && char == "s" {
                self?.onQuickSaveTriggered?()
                return nil
            }
            if mods.contains([.command, .shift]) && char == "d" {
                self?.onTogglePopoverTriggered?()
                return nil
            }
            if mods.contains([.command, .shift]) && char == "x" {
                self?.onScreenshotTriggered?()
                return nil
            }
            return event
        }
    }
    
    public func unregister() {
        if let ref = quickSaveHotKeyRef {
            UnregisterEventHotKey(ref)
            self.quickSaveHotKeyRef = nil
        }
        if let ref = togglePopoverHotKeyRef {
            UnregisterEventHotKey(ref)
            self.togglePopoverHotKeyRef = nil
        }
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            self.screenshotHotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            self.eventHandlerRef = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            self.localMonitor = nil
        }
    }
}
