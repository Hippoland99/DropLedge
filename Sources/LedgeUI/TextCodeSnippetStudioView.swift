import SwiftUI
import CodeAnalysis

public struct SnippetDraft: Identifiable, Sendable {
    public let id: UUID
    public let rawText: String
    public let lineCount: Int
    public let byteSizeFormatted: String
    public let previewLines: [String]
    public let initialExtension: String
    
    public init(rawText: String, initialExtension: String) {
        self.id = UUID()
        self.rawText = rawText
        self.initialExtension = initialExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        
        let lines = rawText.components(separatedBy: .newlines)
        self.lineCount = lines.count
        let byteCount = Int64(rawText.utf8.count)
        self.byteSizeFormatted = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        self.previewLines = Array(lines.prefix(4))
    }
}

public struct TextCodeSnippetStudioView: View {
    public let snippet: SnippetDraft
    public let onSave: (_ fileName: String, _ fileExtension: String) -> Void
    public let onCancel: () -> Void
    
    @State private var fileName: String
    @State private var selectedExtension: String
    @State private var customExtension: String = ""
    
    public static let commonExtensions = ["json", "py", "swift", "md", "txt", "sh", "csv", "env"]
    
    public init(
        snippet: SnippetDraft,
        onSave: @escaping (_ fileName: String, _ fileExtension: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.snippet = snippet
        self.onSave = onSave
        self.onCancel = onCancel
        
        let initialExt = snippet.initialExtension.isEmpty ? "txt" : snippet.initialExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let defaultFileName = "Snippet_\(formatter.string(from: Date()))"
        
        _fileName = State(initialValue: defaultFileName)
        if Self.commonExtensions.contains(initialExt) {
            _selectedExtension = State(initialValue: initialExt)
            _customExtension = State(initialValue: "")
        } else {
            _selectedExtension = State(initialValue: "txt")
            _customExtension = State(initialValue: initialExt)
        }
    }
    
    private var cleanCustomExtension: String {
        customExtension.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
    
    private var activeExtension: String {
        cleanCustomExtension.isEmpty ? selectedExtension : cleanCustomExtension
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            // MARK: 1. Header & Mini-Vorschau
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                        Text("\(snippet.lineCount) Zeilen • \(snippet.byteSizeFormatted)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Auto-Erkennung Badge
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("Auto: .\(snippet.initialExtension)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                    
                    // Schließen Button
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Snippet Studio schließen (Esc)")
                }
                
                // Mini-Vorschau Box (3–4 Zeilen)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(snippet.previewLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .frame(width: 14, alignment: .trailing)
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if snippet.lineCount > 4 {
                        Text("... (\(snippet.lineCount - 4) weitere Zeilen)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .padding(.leading, 20)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            // MARK: 2. Schnell-Auswahl (Pills)
            VStack(alignment: .leading, spacing: 5) {
                Text("Format wählen:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                    ForEach(Self.commonExtensions, id: \.self) { ext in
                        let isSelected = cleanCustomExtension.isEmpty && selectedExtension == ext
                        Button {
                            selectedExtension = ext
                            customExtension = ""
                        } label: {
                            Text(".\(ext)")
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color.accentColor : Color.white.opacity(0.08))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // MARK: 3. Freitext-Feld für Dateiendung
            HStack(spacing: 6) {
                Text("Andere Endung:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 2) {
                    Text(".")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("z.B. yml, sql, dart", text: $customExtension)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(!cleanCustomExtension.isEmpty ? Color.accentColor : Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            
            // MARK: 4. Dateiname-Feld
            VStack(alignment: .leading, spacing: 3) {
                Text("Dateiname:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    TextField("Dateiname", text: $fileName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                    
                    Text(".\(activeExtension)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            
            // MARK: 5. Pipeline Actions
            HStack(spacing: 8) {
                Button {
                    onCancel()
                } label: {
                    Text("Abbrechen")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                
                Button {
                    onSave(fileName, activeExtension)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Als Datei anlegen")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
    }
}
