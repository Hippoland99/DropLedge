import SwiftUI
import AVFoundation
import LedgeCore
import ConversionEngine
import CodeAnalysis
import UniformTypeIdentifiers

public enum PopoverTab: String, CaseIterable, Identifiable {
    case quickActions = "Schnell-Aktionen"
    case editAndCompress = "Anpassen & Komprimieren"
    public var id: String { rawValue }
}

public struct LedgePopoverView: View {
    @State private var appState = AppState.shared
    @State private var selectedTab: PopoverTab = .quickActions
    @State private var isTargetedForDrop: Bool = false
    @State private var actionFeedbackMessage: String?
    
    // Text & Code Snippet Studio State
    @State private var snippetDraft: SnippetDraft? = nil
    
    // PDF-Studio State
    @State private var pdfPageSelectionInput: String = "1-3"
    
    // Freiformat-Auswahl
    @State private var showCustomFormatPicker: Bool = false
    @State private var customFormatInput: String = ""
    
    // Video-Studio State (Trim & Slider)
    @State private var videoDuration: Double = 30.0
    @State private var videoStartTime: Double = 0.0
    @State private var videoEndTime: Double = 30.0
    
    // Bild-Studio State (Kompression)
    @State private var imageQuality: Double = 0.80
    
    public init() {}
    
    private var activeItem: LedgeItem? {
        appState.selectedOrLastDroppedItem ?? appState.lastFourSavedItems.first
    }
    
    private var isVideoItem: Bool {
        guard let url = activeItem?.fileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mov", "mp4", "m4v", "avi", "mkv", "webm"].contains(ext)
    }
    
    private var isImageItem: Bool {
        guard let url = activeItem?.fileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif", "bmp"].contains(ext)
    }
    
    private var isPDFItem: Bool {
        guard let url = activeItem?.fileURL else { return false }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return true }
        if let utType = UTType(filenameExtension: ext), utType.conforms(to: .pdf) { return true }
        return false
    }
    
    private var activeItemFileSizeBytes: Int64? {
        guard let url = activeItem?.fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    private var activeItemFileSizeFormatted: String? {
        guard let bytes = activeItemFileSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func estimatedSavingBadge(ratio: Double) -> String {
        guard let bytes = activeItemFileSizeBytes, bytes > 0 else { return "" }
        let target = Int64(Double(bytes) * ratio)
        let formatted = ByteCountFormatter.string(fromByteCount: target, countStyle: .file)
        let pct = Int((1.0 - ratio) * 100)
        return "~\(formatted) (-\(pct)%)"
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // MARK: 1. Header (Logo + Screenshot-Studio + Pin-Toggle)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 14, weight: .semibold))
                    Text("DropLedge")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
                
                // Screenshot & Extract Button (Cmd + Shift + X)
                Button {
                    ScreenshotStudio.shared.captureInteractiveScreenshot()
                    HapticAudioEngine.shared.play(.screenshotTaken)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Screenshot")
                            .font(.system(size: 11, weight: .medium))
                        Text("⌘⇧X")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Bildschirmausschnitt erfassen & OCR (Cmd + Shift + X)")
                
                // Pin-Toggle-Button (📌 Angepinnt lassen)
                Button {
                    appState.isPinned.toggle()
                    MenuBarController.shared.isPinned = appState.isPinned
                    HapticAudioEngine.shared.play(.pinToggled)
                } label: {
                    Image(systemName: appState.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appState.isPinned ? Color.accentColor : Color.secondary)
                        .padding(5)
                        .background(appState.isPinned ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(appState.isPinned ? "Angepinnt: Schließt nicht beim Klick außerhalb" : "Anpinnen: Fenster dauerhaft offen lassen")
            }
            .padding(.horizontal, 2)
            
            // MARK: 2. Screenshot-Studio Vorschau-Karte (wenn erfasst)
            if let screenshot = appState.capturedScreenshot {
                ScreenshotPreviewCard(
                    screenshot: screenshot,
                    onCopyText: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(screenshot.ocrText, forType: .string)
                        showFeedback("OCR-Text in Zwischenablage kopiert!")
                        HapticAudioEngine.shared.play(.conversionDone)
                    },
                    onSaveImage: {
                        saveScreenshotToLibrary(screenshot)
                    },
                    onOpenPreview: {
                        NSWorkspace.shared.open(screenshot.fileURL)
                    },
                    onDismiss: {
                        withAnimation {
                            appState.capturedScreenshot = nil
                        }
                    }
                )
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }
            
            // Feedback Toast
            if let message = actionFeedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.18))
                .clipShape(Capsule())
                .transition(.opacity)
            }
            
            // MARK: 2.5 Text & Code Snippet Studio (wenn Text eingefügt)
            if let draft = snippetDraft {
                TextCodeSnippetStudioView(
                    snippet: draft,
                    onSave: { fileName, fileExtension in
                        saveSnippetAsFile(fileName: fileName, fileExtension: fileExtension)
                    },
                    onCancel: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            self.snippetDraft = nil
                        }
                    }
                )
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            } else {
                // MARK: 3. Interaktive Drop-Zone mit Finder-Öffner Button & Text-Einfügen Button
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargetedForDrop ? Color.accentColor : Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: isTargetedForDrop ? 2 : 1, dash: isTargetedForDrop ? [6, 4] : [])
                        )
                    
                    VStack(spacing: 6) {
                        if let item = activeItem, let fileURL = item.fileURL {
                            HStack(spacing: 6) {
                                Image(systemName: isVideoItem ? "film.fill" : (isPDFItem ? "doc.text.fill" : (isImageItem ? "photo.fill" : "doc.fill")))
                                    .font(.system(size: 11))
                                    .foregroundStyle(isVideoItem ? .indigo : (isPDFItem ? .red : .blue))
                                Text(fileURL.lastPathComponent)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                if let size = activeItemFileSizeFormatted {
                                    Text("• \(size)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.24))
                            .clipShape(Capsule())
                        }
                        
                        Text(isTargetedForDrop ? "Datei jetzt loslassen" : "Dateien oder Videos hier ablegen")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isTargetedForDrop ? .primary : .secondary)
                        
                        // Button-Reihe: Finder-Öffner + Text & Code Snippet Studio
                        HStack(spacing: 8) {
                            // Großer Finder-Öffner Button ([ + ] Datei auswählen)
                            Button {
                                openFinderFilePicker()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("[ + ] Datei auswählen")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.18))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Vollwertigen Finder-Dialog im Vordergrund öffnen")
                            
                            // [ 📋 ] Einfügen Button (Cmd + V: Dateien, Screenshots, Bilder, Text)
                            Button {
                                pasteFromClipboard()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("[ 📋 ] Einfügen")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.purple.opacity(0.18))
                                .foregroundStyle(Color.purple)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.purple.opacity(0.35), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut("v", modifiers: .command)
                            .help("Inhalt aus Zwischenablage einfügen: Dateien, Screenshots, Bilder oder Text (Cmd + V)")
                        }
                    }
                    .padding(.vertical, 10)
                }
                .frame(height: 98)
                .dropDestination(for: URL.self) { items, _ in
                    guard !items.isEmpty else { return false }
                    appState.handleDrop(in: .smartSave, urls: items, text: nil)
                    HapticAudioEngine.shared.play(.dropSuccess)
                    return true
                } isTargeted: { targeted in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isTargetedForDrop = targeted
                    }
                }
                
                // MARK: 4. Native Progress Bar bei Konvertierung
                if appState.isConverting {
                    VStack(spacing: 5) {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(Color.accentColor)
                        
                        Text(appState.conversionStatusMessage ?? "Verarbeitung läuft...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity.combined(with: .scale))
                }
                
                // MARK: 5. Reiter-Umschalter: [ Schnell-Aktionen ] vs [ Anpassen & Komprimieren ]
                Picker("", selection: $selectedTab) {
                    ForEach(PopoverTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 2)
                
                // MARK: 6. Inhalt je nach Reiter
                if selectedTab == .quickActions {
                    quickActionsSection
                } else {
                    editAndCompressSection
                }
            }
            
            Divider().opacity(0.4)
            
            // MARK: 7. Scratchpad mit Drag-OUT & Lösch-Button (✕)
            scratchpadSection
        }
        .padding(14)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .task(id: activeItem?.id) {
            await loadVideoMetadata()
        }
    }
    
    // MARK: - View Sections
    
    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(spacing: 5) {
            if isVideoItem {
                // 4 Video-Aktionen
                ActionRowButton(
                    title: "Zu MP4 (H.264 / Web)",
                    subtitle: "Universelles Web-Format via AVFoundation",
                    icon: "film.fill",
                    accentColor: .blue,
                    isDisabled: appState.isConverting
                ) {
                    runVideoConversion { try await LedgeCoordinator.shared.convertToWebMP4(url: $0) }
                }
                
                ActionRowButton(
                    title: "In animiertes GIF (15 FPS)",
                    subtitle: "Verlustfreie Keyframe-Extraktion",
                    icon: "play.square.stack.fill",
                    accentColor: .pink,
                    isDisabled: appState.isConverting
                ) {
                    runVideoConversion { try await LedgeCoordinator.shared.convertToAnimatedGIF(url: $0, fps: 15) }
                }
                
                ActionRowButton(
                    title: "Für Discord/Slack (<25MB)",
                    subtitle: "Bitrate-Optimierung auf Upload-Limit",
                    icon: "arrow.down.right.and.arrow.up.left",
                    accentColor: .purple,
                    isDisabled: appState.isConverting
                ) {
                    runVideoConversion { try await LedgeCoordinator.shared.compressVideoToTargetSize(url: $0, targetMB: 24.0) }
                }
                
                ActionRowButton(
                    title: "Audio extrahieren (M4A)",
                    subtitle: "Reine Tonspur als AAC/M4A speichern",
                    icon: "waveform",
                    accentColor: .green,
                    isDisabled: appState.isConverting
                ) {
                    runVideoConversion { try await LedgeCoordinator.shared.extractAudio(url: $0) }
                }
            } else if isPDFItem {
                // 4 PDF-Aktionen
                ActionRowButton(
                    title: "PDF komprimieren (150 DPI)",
                    subtitle: "Smartes Rendering & JPEG-Kompression \(estimatedSavingBadge(ratio: 0.30))",
                    icon: "arrow.down.doc.fill",
                    accentColor: .blue,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runPDFCompression(maxDPI: 150, quality: 0.65, tag: "150DPI")
                }
                
                ActionRowButton(
                    title: "Extrem verkleinern (72 DPI für Mail)",
                    subtitle: "Maximale Ersparnis für E-Mail-Anhänge \(estimatedSavingBadge(ratio: 0.15))",
                    icon: "envelope.badge.fill",
                    accentColor: .indigo,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runPDFCompression(maxDPI: 72, quality: 0.50, tag: "Mail_72DPI")
                }
                
                ActionRowButton(
                    title: "Nur 1. Seite extrahieren",
                    subtitle: "Titelseite / Rechnung als Einzeldokument",
                    icon: "doc.badge.arrow.up",
                    accentColor: .orange,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runPDFExtractFirstPage()
                }
                
                ActionRowButton(
                    title: "OCR-Text kopieren",
                    subtitle: "On-Device Texterkennung aller Seiten",
                    icon: "doc.text.viewfinder",
                    accentColor: .teal,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runOCRExtraction()
                }
            } else if isImageItem {
                // 4 Bild-Aktionen
                ActionRowButton(
                    title: "In WebP konvertieren",
                    subtitle: "Maximale Kompression für Web & Apps",
                    icon: "photo.badge.arrow.forward",
                    accentColor: .blue,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runImageConversion(format: .webp)
                }
                
                ActionRowButton(
                    title: "In PNG konvertieren",
                    subtitle: "Verlustfreies Standard-Grafikformat",
                    icon: "photo.fill",
                    accentColor: .cyan,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runImageConversion(format: .png)
                }
                
                ActionRowButton(
                    title: "EXIF-Metadaten entfernen",
                    subtitle: "GPS, Kamera & Zeitstempel bereinigen",
                    icon: "shield.slash.fill",
                    accentColor: .indigo,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runEXIFSanitizing()
                }
                
                ActionRowButton(
                    title: "OCR-Text kopieren",
                    subtitle: "On-Device Texterkennung via Neural Engine",
                    icon: "doc.text.viewfinder",
                    accentColor: .orange,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runOCRExtraction()
                }
            } else {
                // 4 Text/Code-Aktionen
                ActionRowButton(
                    title: "Inhalt kopieren",
                    subtitle: "Vollständigen Text in Zwischenablage",
                    icon: "doc.on.clipboard.fill",
                    accentColor: .blue,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    copyTextContent()
                }
                
                ActionRowButton(
                    title: "In Markdown formatieren",
                    subtitle: "Als .md mit Codeblock exportieren",
                    icon: "text.quote",
                    accentColor: .cyan,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runCustomFormatConversion(ext: "md")
                }
                
                ActionRowButton(
                    title: "JSON validieren & formatieren",
                    subtitle: "Formatierter JSON-Payload",
                    icon: "curlybraces",
                    accentColor: .green,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runCustomFormatConversion(ext: "json")
                }
                
                ActionRowButton(
                    title: "In Swift-Snippet wandeln",
                    subtitle: "Exportiert als .swift Datei",
                    icon: "swift",
                    accentColor: .orange,
                    isDisabled: activeItem?.fileURL == nil || appState.isConverting
                ) {
                    runCustomFormatConversion(ext: "swift")
                }
            }
            
            // Button "Anderes Format..."
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    showCustomFormatPicker.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                    Text(showCustomFormatPicker ? "Format-Auswahl schließen" : "Anderes Format...")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: showCustomFormatPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            
            if showCustomFormatPicker {
                customFormatPickerView
            }
        }
    }
    
    @ViewBuilder
    private var editAndCompressSection: some View {
        VStack(spacing: 8) {
            // Vorher-Größenanzeige
            if let sizeFormatted = activeItemFileSizeFormatted {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text("Originalgröße: \(sizeFormatted)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 2)
            }
            
            if isVideoItem {
                // VIDEO STUDIO: Trimmen & Zielgrößen-Kompression
                VStack(alignment: .leading, spacing: 7) {
                    // Trimming Header & Zeitangabe
                    HStack {
                        Label("VIDEO TRIMMEN", systemImage: "timeline.selection")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(formatSeconds(videoStartTime)) – \(formatSeconds(videoEndTime)) (\(formatSeconds(videoEndTime - videoStartTime)))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    
                    // Slider 1: Start-Zeit
                    HStack(spacing: 6) {
                        Text("Start")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Slider(value: $videoStartTime, in: 0...max(0.1, videoEndTime - 0.1))
                    }
                    
                    // Slider 2: Ende-Zeit
                    HStack(spacing: 6) {
                        Text("Ende")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Slider(value: $videoEndTime, in: min(videoDuration, videoStartTime + 0.1)...videoDuration)
                    }
                    
                    // Trim Button
                    Button {
                        runVideoConversion { try await LedgeCoordinator.shared.trimVideo(url: $0, startTime: videoStartTime, endTime: videoEndTime) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "scissors")
                            Text("Ausschnitt trimmen (\(formatSeconds(videoEndTime - videoStartTime)))")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isConverting)
                    
                    Divider().opacity(0.3)
                    
                    // Zielgrößen-Kompression Schnellbuttons
                    Text("ZIELGRÖSSE & EXPORT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 6) {
                        Button {
                            runVideoConversion { try await LedgeCoordinator.shared.compressVideoToTargetSize(url: $0, targetMB: 24.0) }
                        } label: {
                            Text("[ < 25 MB ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.purple.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Für Discord & Slack (< 25 MB)")
                        
                        Button {
                            runVideoConversion { try await LedgeCoordinator.shared.compressVideoToTargetSize(url: $0, targetMB: 9.5) }
                        } label: {
                            Text("[ < 10 MB ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.indigo.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Für E-Mail-Anhänge (< 10 MB)")
                        
                        Button {
                            runVideoConversion { try await LedgeCoordinator.shared.convertToAnimatedGIF(url: $0, fps: 15) }
                        } label: {
                            Text("[ Zu GIF ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.pink.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("In animiertes GIF (15 FPS)")
                    }
                }
            } else if isPDFItem {
                // PDF STUDIO: Kompression & Seiten-Studio
                VStack(alignment: .leading, spacing: 7) {
                    Text("PDF KOMPRESSION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Button {
                        runPDFCompression(maxDPI: 150, quality: 0.65, tag: "150DPI")
                    } label: {
                        HStack {
                            Text("📉 PDF komprimieren (150 DPI)")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text(estimatedSavingBadge(ratio: 0.30))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isConverting)
                    
                    Button {
                        runPDFCompression(maxDPI: 72, quality: 0.50, tag: "Mail_72DPI")
                    } label: {
                        HStack {
                            Text("✉️ Extrem verkleinern (72 DPI für Mail)")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text(estimatedSavingBadge(ratio: 0.15))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isConverting)
                    
                    // Trennlinie: Seiten-Auswahl
                    HStack(spacing: 8) {
                        Text("Seiten-Auswahl")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        VStack { Divider().opacity(0.3) }
                    }
                    .padding(.top, 3)
                    
                    Button {
                        runPDFExtractFirstPage()
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.arrow.up")
                            Text("Nur 1. Seite extrahieren")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text("Titelseite / Deckblatt")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isConverting)
                    
                    // Textfeld: Seiten: [ 1-3, 5 ] mit Button [ ✂️ Extrahieren ]
                    HStack(spacing: 6) {
                        Text("Seiten:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("z.B. 1-3, 5", text: $pdfPageSelectionInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        
                        Button {
                            runPDFExtractPages(selection: pdfPageSelectionInput)
                        } label: {
                            HStack(spacing: 4) {
                                Text("✂️ Extrahieren")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(pdfPageSelectionInput.trimmingCharacters(in: .whitespaces).isEmpty || appState.isConverting)
                    }
                }
            } else {
                // BILD STUDIO: Seitenverhältnis-Crop, Skalierung & Qualitäts-Slider
                VStack(alignment: .leading, spacing: 7) {
                    // Seitenverhältnis-Zuschnitt
                    Text("SEITENVERHÄLTNIS ZUSCHNEIDEN (CROP)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 6) {
                        Button {
                            runImageCrop(ratio: .square)
                        } label: {
                            Text("[ 1:1 Quadrat ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            runImageCrop(ratio: .landscape16_9)
                        } label: {
                            Text("[ 16:9 Quer ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.cyan.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            runImageCrop(ratio: .portrait9_16)
                        } label: {
                            Text("[ 9:16 Story ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.teal.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Skalierung (Resize)
                    Text("SKALIERUNG & GRÖSSE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 6) {
                        Button {
                            runImageResize(scale: 0.5)
                        } label: {
                            Text("[ -50% Größe ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.purple.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            runImageResize(maxWidth: 1920)
                        } label: {
                            Text("[ Max 1920px ]")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.indigo.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Kompression & Qualitäts-Schieberegler
                    HStack {
                        Text("KOMPRESSION & QUALITÄT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(imageQuality * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    
                    Slider(value: $imageQuality, in: 0.20...1.0, step: 0.05)
                    
                    HStack(spacing: 6) {
                        Button {
                            imageQuality = 0.80
                            runImageCompression(quality: 0.80)
                        } label: {
                            Text("Web-Optimiert (80%)")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            imageQuality = 1.0
                            runImageCompression(quality: 1.0)
                        } label: {
                            Text("Verlustfrei (100%)")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    @ViewBuilder
    private var customFormatPickerView: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestedFormats, id: \.self) { format in
                        Button {
                            runCustomFormatConversion(ext: format)
                        } label: {
                            Text(format.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            
            HStack(spacing: 6) {
                TextField("Beliebige Endung (z.B. webp, mp4, heic, json)", text: $customFormatInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                
                Button("Konvertieren") {
                    guard !customFormatInput.isEmpty else { return }
                    runCustomFormatConversion(ext: customFormatInput)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(customFormatInput.trimmingCharacters(in: .whitespaces).isEmpty || activeItem?.fileURL == nil)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    @ViewBuilder
    private var scratchpadSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SCRATCHPAD (DRAG OUT)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Mit Maus herausziehen")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            
            if appState.lastFourSavedItems.isEmpty {
                HStack {
                    Spacer()
                    Text("Noch keine Dateien abgelegt")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                    Spacer()
                }
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 4) {
                    ForEach(appState.lastFourSavedItems) { item in
                        ScratchpadCardRow(
                            item: item,
                            isSelected: activeItem?.id == item.id,
                            onSelect: {
                                appState.selectedOrLastDroppedItem = item
                            },
                            onDelete: {
                                let isExternal = (item.savedURL == nil || item.savedURL == item.originalURL)
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    appState.removeItem(item, moveToTrash: true)
                                }
                                if isExternal {
                                    showFeedback("Vom Scratchpad entfernt (Originaldatei bleibt erhalten)")
                                } else {
                                    showFeedback("Datei in Papierkorb verschoben")
                                }
                                HapticAudioEngine.shared.play(.deleteItem)
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers & Data Loading
    
    private var suggestedFormats: [String] {
        if isVideoItem {
            return ["mp4", "gif", "m4a", "mov"]
        } else if isImageItem {
            return ["webp", "png", "jpeg", "heic", "tiff", "bmp", "pdf"]
        } else {
            return ["txt", "md", "json", "swift", "py", "sh"]
        }
    }
    
    private func loadVideoMetadata() async {
        guard let url = activeItem?.fileURL, isVideoItem else { return }
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let sec = CMTimeGetSeconds(duration)
            if sec > 0.1 {
                self.videoDuration = sec
                self.videoStartTime = 0.0
                self.videoEndTime = sec
            }
        }
    }
    
    private func formatSeconds(_ sec: Double) -> String {
        let total = Int(max(0, sec))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    // MARK: - Bugfix: NSOpenPanel im Vordergrund
    
    private func openFinderFilePicker() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.level = .modalPanel
            panel.title = "Dateien für DropLedge auswählen"
            panel.prompt = "Auswählen"
            
            let wasPinned = appState.isPinned
            if !wasPinned {
                MenuBarController.shared.setTemporaryPinned(true)
            }
            
            let response = panel.runModal()
            if !wasPinned {
                MenuBarController.shared.setTemporaryPinned(false)
            }
            
            if response == .OK && !panel.urls.isEmpty {
                appState.handleDrop(in: .smartSave, urls: panel.urls, text: nil)
                HapticAudioEngine.shared.play(.dropSuccess)
            }
        }
    }
    
    // MARK: - Clipboard Paste Ingestion (Files, Screenshots, Images, Code & Text)
    
    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        
        // 1. Dateien aus Finder / Dateimanager (Cmd + C)
        let fileURLs = getFileURLsFromPasteboard()
        if !fileURLs.isEmpty {
            appState.handleDrop(in: .smartSave, urls: fileURLs, text: nil)
            HapticAudioEngine.shared.play(.dropSuccess)
            let desc = fileURLs.count == 1 ? fileURLs[0].lastPathComponent : "\(fileURLs.count) Dateien"
            showFeedback("\(desc) aus Zwischenablage eingefügt")
            return
        }
        
        // 2. Screenshots & Bilder aus der Zwischenablage (Cmd + Ctrl + Shift + 4, Browser, etc.)
        if let imageData = extractImageDataFromPasteboard() {
            handlePastedImageData(imageData)
            return
        }
        
        // 3. Code- oder Text-Snippets
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let classification = CodeClassifier.classify(rawText: text)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.snippetDraft = SnippetDraft(rawText: text, initialExtension: classification.fileExtension)
            }
            HapticAudioEngine.shared.play(.dropSuccess)
            showFeedback("Code/Text erkannt (\(classification.language.rawValue))")
            return
        }
        
        // 4. Nicht unterstütztes Format oder leere Zwischenablage
        showFeedback("Zwischenablage ist leer oder enthält kein unterstütztes Format!")
    }
    
    private func pasteTextFromClipboard() {
        pasteFromClipboard()
    }
    
    private func getFileURLsFromPasteboard() -> [URL] {
        let pasteboard = NSPasteboard.general
        var urls: [URL] = []
        
        // Method 1: readObjects for NSURL mit urlReadingFileURLsOnly
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in objects where url.isFileURL && FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                if !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        
        // Method 2: Fallback auf filenames property list (klassischer Finder Pasteboard-Typ)
        if urls.isEmpty, let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for path in filenames {
                let u = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: u.path(percentEncoded: false)) && !urls.contains(u) {
                    urls.append(u)
                }
            }
        }
        
        // Method 3: Fallback auf public.file-url String
        if urls.isEmpty, let urlString = pasteboard.string(forType: NSPasteboard.PasteboardType("public.file-url")),
           let u = URL(string: urlString), u.isFileURL,
           FileManager.default.fileExists(atPath: u.path(percentEncoded: false)) {
            urls.append(u)
        }
        
        return urls
    }
    
    private func extractImageDataFromPasteboard() -> Data? {
        let pasteboard = NSPasteboard.general
        
        // 1. Direkte PNG-Daten
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return pngData
        }
        
        // 2. Direkte TIFF-Daten -> als PNG kodieren
        if let tiffData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }
        
        // 3. Fallback über NSImage (unterstützt Screenshots aus vielen Apps)
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }
        
        return nil
    }
    
    private func handlePastedImageData(_ imageData: Data) {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempFileURL = tempDir.appendingPathComponent("DropLedge_Pasted_\(timestamp).png")
        
        do {
            try imageData.write(to: tempFileURL, options: .atomic)
        } catch {
            showFeedback("Fehler beim Speichern: \(error.localizedDescription)")
            return
        }
        
        HapticAudioEngine.shared.play(.dropSuccess)
        showFeedback("Screenshot/Bild aus Zwischenablage geladen...")
        
        Task {
            let coordinator = LedgeCoordinator.shared
            let baseDir = appState.libraryDirectory
            
            var savedURL = tempFileURL
            var detectedText: String? = nil
            
            do {
                let result = try await coordinator.processDroppedImage(
                    data: imageData,
                    fileExtension: "png",
                    baseDirectory: baseDir,
                    sourceApp: "ClipboardScreenshot"
                )
                savedURL = result.savedURL
                detectedText = result.ocrText
            } catch {
                print("[DropLedge] Fehler beim Speichern des Bildes in Library: \(error)")
            }
            
            let captured = CapturedScreenshot(
                fileURL: savedURL,
                ocrText: detectedText ?? ""
            )
            
            let item = LedgeItem(
                originalURL: tempFileURL,
                savedURL: savedURL,
                timestamp: Date(),
                contentType: .image,
                suggestedFileName: savedURL.lastPathComponent,
                extractedText: detectedText,
                tags: ["Screenshot", "Pasted"]
            )
            
            await MainActor.run {
                appState.capturedScreenshot = captured
                appState.addOrUpdateItem(item)
                if let text = detectedText, !text.isEmpty {
                    showFeedback("Screenshot eingefügt & Text erkannt!")
                } else {
                    showFeedback("Screenshot/Bild in DropLedge eingefügt!")
                }
            }
        }
    }
    
    private func saveSnippetAsFile(fileName: String, fileExtension: String) {
        guard let draft = snippetDraft else { return }
        
        Task {
            do {
                let savedURL = try await appState.createSnippetFile(
                    text: draft.rawText,
                    fileName: fileName,
                    fileExtension: fileExtension
                )
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    self.snippetDraft = nil
                }
                showFeedback("Snippet angelegt: \(savedURL.lastPathComponent)")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Action Handlers
    
    private func runPDFCompression(maxDPI: CGFloat, quality: CGFloat, tag: String) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        appState.isConverting = true
        appState.conversionStatusMessage = "Komprimiere PDF (\(Int(maxDPI)) DPI)..."
        
        Task {
            do {
                let compressedURL = try await LedgeCoordinator.shared.compressPDF(url: url, maxDPI: maxDPI, quality: quality)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: compressedURL,
                    timestamp: Date(),
                    contentType: .pdf,
                    suggestedFileName: compressedURL.lastPathComponent,
                    tags: ["PDF", tag],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("PDF erfolgreich komprimiert (\(item.sizeSavingsBadge ?? ""))!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runPDFExtractFirstPage() {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        appState.isConverting = true
        appState.conversionStatusMessage = "Extrahiere 1. Seite..."
        
        Task {
            do {
                let extractedURL = try await LedgeCoordinator.shared.extractFirstPDFPage(url: url)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: extractedURL,
                    timestamp: Date(),
                    contentType: .pdf,
                    suggestedFileName: extractedURL.lastPathComponent,
                    tags: ["PDF", "Page1"],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("1. Seite extrahiert: \(extractedURL.lastPathComponent)")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runPDFExtractPages(selection: String) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        let clean = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        appState.isConverting = true
        appState.conversionStatusMessage = "Extrahiere Seiten \(clean)..."
        
        Task {
            do {
                let extractedURL = try await LedgeCoordinator.shared.extractPDFPages(url: url, pageSelection: clean)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: extractedURL,
                    timestamp: Date(),
                    contentType: .pdf,
                    suggestedFileName: extractedURL.lastPathComponent,
                    tags: ["PDF", "Pages"],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("Seiten extrahiert: \(extractedURL.lastPathComponent)")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runVideoConversion(operation: @escaping (URL) async throws -> URL) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        appState.isConverting = true
        appState.conversionStatusMessage = "Transkodiere Video..."
        
        Task {
            do {
                let convertedURL = try await operation(url)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: convertedURL,
                    timestamp: Date(),
                    contentType: .movie,
                    suggestedFileName: convertedURL.lastPathComponent,
                    tags: ["Converted"],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("Video erfolgreich exportiert!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runImageCrop(ratio: OmniConverterEngine.AspectRatioPreset) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        appState.isConverting = true
        appState.conversionStatusMessage = "Schneide Seitenverhältnis zu..."
        
        Task {
            do {
                let croppedURL = try await LedgeCoordinator.shared.cropImage(url: url, aspectRatio: ratio)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: croppedURL,
                    timestamp: Date(),
                    contentType: .image,
                    suggestedFileName: croppedURL.lastPathComponent,
                    tags: ["Crop-\(ratio.rawValue)"],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("Auf \(ratio.rawValue) zugeschnitten!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runImageResize(scale: Double? = nil, maxWidth: CGFloat? = nil) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        appState.isConverting = true
        appState.conversionStatusMessage = "Skaliere Bild..."
        
        Task {
            do {
                let resizedURL = try await LedgeCoordinator.shared.resizeImage(url: url, scale: scale, maxWidth: maxWidth)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: resizedURL,
                    timestamp: Date(),
                    contentType: .image,
                    suggestedFileName: resizedURL.lastPathComponent,
                    tags: ["Resized"],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("Bild erfolgreich skaliert!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runImageCompression(quality: Double) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        appState.isConverting = true
        appState.conversionStatusMessage = "Komprimiere Bild..."
        
        Task {
            do {
                let compressedURL = try await LedgeCoordinator.shared.compressImage(url: url, quality: quality)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: compressedURL,
                    timestamp: Date(),
                    contentType: .image,
                    suggestedFileName: compressedURL.lastPathComponent,
                    tags: ["Q\(Int(quality * 100))"],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("Bild auf \(Int(quality * 100))% komprimiert!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runImageConversion(format: OmniConverterEngine.ImageTargetFormat) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        appState.isConverting = true
        appState.conversionStatusMessage = "Konvertiere Bild zu \(format.rawValue.uppercased())..."
        
        Task {
            do {
                let convertedURL = try await LedgeCoordinator.shared.convertImage(url: url, to: format)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: convertedURL,
                    timestamp: Date(),
                    contentType: .image,
                    suggestedFileName: convertedURL.lastPathComponent,
                    tags: [format.rawValue.uppercased()],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("Bild als \(format.rawValue.uppercased()) konvertiert!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runCustomFormatConversion(ext: String) {
        guard let url = activeItem?.fileURL else { return }
        let originalSize = activeItemFileSizeBytes
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        guard !clean.isEmpty else { return }
        
        appState.isConverting = true
        appState.conversionStatusMessage = "Konvertiere zu .\(clean)..."
        
        Task {
            do {
                let convertedURL = try await LedgeCoordinator.shared.convertToCustomFormat(url: url, targetExtension: clean)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: convertedURL,
                    timestamp: Date(),
                    contentType: UTType(filenameExtension: clean) ?? .item,
                    suggestedFileName: convertedURL.lastPathComponent,
                    tags: [clean.uppercased()],
                    originalSizeBytes: originalSize
                )
                appState.addOrUpdateItem(item)
                showFeedback("Erfolgreich als .\(clean) exportiert!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Fehler: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runEXIFSanitizing() {
        guard let url = activeItem?.fileURL else { return }
        appState.isConverting = true
        appState.conversionStatusMessage = "Bereinige EXIF & GPS Metadaten..."
        
        Task {
            do {
                let sanitizedURL = try await LedgeCoordinator.shared.stripMetadata(url: url)
                let item = LedgeItem(
                    originalURL: url,
                    savedURL: sanitizedURL,
                    timestamp: Date(),
                    contentType: .image,
                    suggestedFileName: sanitizedURL.lastPathComponent,
                    tags: ["Sanitized"]
                )
                appState.addOrUpdateItem(item)
                showFeedback("EXIF-Metadaten vollständig entfernt!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Bereinigung fehlgeschlagen: \(error.localizedDescription)")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func runOCRExtraction() {
        guard let url = activeItem?.fileURL else { return }
        appState.isConverting = true
        appState.conversionStatusMessage = "Führe Texterkennung aus..."
        
        Task {
            do {
                let ocrText = try await LedgeCoordinator.shared.extractOCRText(from: url)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ocrText, forType: .string)
                showFeedback("OCR-Text in Zwischenablage kopiert!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Kein Text im Bild erkannt")
            }
            appState.isConverting = false
            appState.conversionStatusMessage = nil
        }
    }
    
    private func copyTextContent() {
        guard let url = activeItem?.fileURL else { return }
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            showFeedback("Text in Zwischenablage kopiert!")
            HapticAudioEngine.shared.play(.conversionDone)
        }
    }
    
    private func saveScreenshotToLibrary(_ screenshot: CapturedScreenshot) {
        Task {
            do {
                let data = try Data(contentsOf: screenshot.fileURL)
                let saved = try await LedgeCoordinator.shared.processDroppedImage(
                    data: data,
                    fileExtension: "png",
                    baseDirectory: appState.libraryDirectory,
                    sourceApp: "ScreenshotStudio"
                )
                let item = LedgeItem(
                    originalURL: screenshot.fileURL,
                    savedURL: saved.savedURL,
                    timestamp: Date(),
                    contentType: .image,
                    suggestedFileName: saved.savedURL.lastPathComponent,
                    extractedText: screenshot.ocrText,
                    tags: ["Screenshot"]
                )
                appState.addOrUpdateItem(item)
                showFeedback("Screenshot in Bibliothek gespeichert!")
                HapticAudioEngine.shared.play(.conversionDone)
            } catch {
                showFeedback("Speichern fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }
    
    private func showFeedback(_ text: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            actionFeedbackMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if actionFeedbackMessage == text {
                    actionFeedbackMessage = nil
                }
            }
        }
    }
}

// MARK: - Subcomponents

private struct ScreenshotPreviewCard: View {
    let screenshot: CapturedScreenshot
    let onCopyText: () -> Void
    let onSaveImage: () -> Void
    let onOpenPreview: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Screenshot erfasst", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            
            if !screenshot.ocrText.isEmpty {
                Text(screenshot.ocrText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            
            HStack(spacing: 6) {
                Button(action: onCopyText) {
                    Label("Text kopieren", systemImage: "doc.on.clipboard.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                
                Button(action: onSaveImage) {
                    Label("Speichern", systemImage: "square.and.arrow.down.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                
                Button(action: onOpenPreview) {
                    Label("Vorschau", systemImage: "arrow.up.forward.app.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct ActionRowButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isDisabled ? Color.white.opacity(0.04) : accentColor.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDisabled ? Color.secondary : accentColor)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct ScratchpadCardRow: View {
    let item: LedgeItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            if let url = item.fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileURL?.lastPathComponent ?? item.suggestedFileName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 4) {
                    Text(item.contentType.localizedDescription ?? item.contentType.identifier)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if let badge = item.sizeSavingsBadge {
                        Text(badge)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(item.hasSavings ? Color.green : Color.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(item.hasSavings ? Color.green.opacity(0.18) : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Lösch-Button (✕) oben rechts bei Hover oder Selektion
            if isHovered || isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Aus Scratchpad entfernen & in Papierkorb verschieben")
                .transition(.opacity)
            } else {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.white.opacity(0.07) : Color.white.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
        // DRAG-OUT: Dateinamen-Fix (Verwendet zwingend Dateireferenz & suggestedName)
        .onDrag {
            HapticAudioEngine.shared.play(.dragOut)
            guard let fileURL = item.fileURL else { return NSItemProvider() }
            let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: fileURL as NSURL)
            provider.suggestedName = fileURL.lastPathComponent
            return provider
        }
    }
}
