import AppKit
import SwiftUI
import LedgeCore

@MainActor
final class StatusItemDragOverlayView: NSView {
    var onDropURLs: (([URL]) -> Void)?
    var onClick: (() -> Void)?
    private var isHighlighted: Bool = false {
        didSet { needsDisplay = true }
    }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .string,
            NSPasteboard.PasteboardType("public.file-url")
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isHighlighted = true
        return .copy
    }
    
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isHighlighted = false
    }
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isHighlighted = false
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            onDropURLs?(urls)
            return true
        }
        return false
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
            path.fill()
        }
    }
}

@MainActor
public final class MenuBarController {
    public static let shared = MenuBarController()
    
    public private(set) var statusItem: NSStatusItem?
    public private(set) var popover: NSPopover?
    private var dragOverlay: StatusItemDragOverlayView?
    
    /// Steuert das Pin-Verhalten des Popovers
    public var isPinned: Bool = false {
        didSet {
            popover?.behavior = isPinned ? .applicationDefined : .transient
        }
    }
    
    private init() {}
    
    public func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item
        
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "DropLedge")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            
            let overlay = StatusItemDragOverlayView(frame: button.bounds)
            overlay.autoresizingMask = [.width, .height]
            
            overlay.onClick = { [weak self] in
                self?.togglePopover()
            }
            
            overlay.onDropURLs = { urls in
                Task { @MainActor in
                    AppState.shared.handleDrop(in: .scratchpad, urls: urls, text: nil)
                    HapticAudioEngine.shared.play(.dropSuccess)
                }
            }
            
            button.addSubview(overlay)
            self.dragOverlay = overlay
        }
        
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 360, height: 560)
        pop.contentViewController = NSHostingController(rootView: LedgePopoverView())
        self.popover = pop
    }
    
    public func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.level = .floating
                window.makeKey()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    public func showPopover() {
        guard let popover = popover, let button = statusItem?.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.level = .floating
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closePopover() {
        popover?.performClose(nil)
    }
    
    public func setTemporaryPinned(_ pinned: Bool) {
        popover?.behavior = (pinned || isPinned) ? .applicationDefined : .transient
    }
}
