import AppKit
import Combine

@MainActor
public final class ClipboardMonitor: ObservableObject {
    public static let shared = ClipboardMonitor()
    
    private var timer: Timer?
    private var lastChangeCount: Int
    private let pasteboard = NSPasteboard.general
    
    public var onClipboardChanged: ((NSPasteboard) -> Void)?
    public private(set) var isMonitoring: Bool = false
    
    public init() {
        self.lastChangeCount = pasteboard.changeCount
    }
    
    public func startMonitoring(interval: TimeInterval = 0.5) {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForChanges()
            }
        }
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }
    
    public func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        onClipboardChanged?(pasteboard)
    }
}
