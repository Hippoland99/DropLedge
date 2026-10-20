import Foundation

public enum DropZoneType: String, Sendable, CaseIterable {
    case smartSave = "Smart Save"
    case actionPipeline = "Action Pipeline"
    case scratchpad = "Scratchpad"
    
    public var title: String { rawValue }
    
    public var subtitle: String {
        switch self {
        case .smartSave:
            return "Auto-organize, timestamp & tags"
        case .actionPipeline:
            return "Instant OCR, convert & sanitize"
        case .scratchpad:
            return "Temporary shelf for drag-out"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .smartSave:
            return "arrow.down.doc.fill"
        case .actionPipeline:
            return "bolt.fill"
        case .scratchpad:
            return "tray.and.arrow.down.fill"
        }
    }
}
