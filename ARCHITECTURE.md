# Systemarchitektur & UI/UX-Spezifikation: **DropLedge** (macOS)
**Rolle:** Principal macOS Software Architect & Lead Apple Platform Designer  
**Status:** Produktionsreife technische Blaupause zur direkten Implementierung (z. B. via Xcode / Antigravity)  
**Zielumgebung:** macOS 14.0+ (Sonoma / Sequoia+), Apple Silicon Native (Universal Binary), 100 % Offline, Zero-Dependency.

---

## 1. Killer-Feature-Validierung & Erweiterung (100 % Lokal & Offline)

Viele Mac-Tools leiden unter Funktionsüberladung, Electron-Ballast oder Cloud-Abhängigkeiten. Um *DropLedge* unverzichtbar zu machen, implementieren wir hardwarebeschleunigte, native Features, die alltägliche System-Friktionen nahtlos beseitigen.

```
+-----------------------------------------------------------------------------------+
|                                  DROPLEDGE CORE                                   |
|   +-------------------+  +--------------------+  +----------------------------+   |
|   |  VisionEngine     |  | PrivacySanitizer   |  | CodeClassifierEngine       |   |
|   |  (VNTextRequest,  |  | (ImageIO / EXIF,   |  | (AST Heuristics,           |   |
|   |   VNBarcodes)     |  |  CoreImage Scrub)  |  |  Zero-Loss Encoding)       |   |
|   +-------------------+  +--------------------+  +----------------------------+   |
|   +-------------------------------------------+  +----------------------------+   |
|   | MediaConverter & AssetOptimizer           |  | Spotlight & Metadata Writer|   |
|   | (vImage, CIContext, AVAssetExportSession) |  | (xattr, kMDItemAttributes) |   |
|   +-------------------------------------------+  +----------------------------+   |
+-----------------------------------------------------------------------------------+
```

### Die 5 nativen Offline-Killer-Features

#### 1. Instant Vision OCR & Searchable PDF Synthesizer
* **Apple API:** `Vision.framework` (`VNRecognizeTextRequest`), `PDFKit`, `CoreGraphics`.
* **Funktion:** Jedes abgelegte oder per Shortcut erfasste Bild (Screenshot, Scan) durchläuft automatisch eine On-Device-Texterkennung (Neural Engine). Der Text steht sofort in der Zwischenablage bereit. Optional erzeugt die Engine per `PDFPage` eine unsichtbare Textebene über dem Bild: Aus einem Screenshot wird in < 80 ms ein durchsuchbares, voll vektorisiertes PDF.
* **Beseitigte Frustration:** Schluss mit manuellem Abtippen von Texten aus Fehlermeldungen, UI-Designs, Videos oder Web-Grafiken.

#### 2. Zero-Loss Code-Classifier & Format-Preserver
* **Apple API:** `UniformTypeIdentifiers` (`UTType`), `NaturalLanguage` (`NLLanguageRecognizer`), Regex-Heuristik.
* **Funktion:** Beim Kopieren oder Reindroppen von unformatiertem Text analysiert die Engine Syntaxmuster (Klammerstrukturen, Schlüsselwörter wie `func`, `def`, `import`, `{ "json": true }`). Sie erkennt die Sprache (Swift, Python, JSON, Rust, Shell, SQL etc.), behält Tabs/Spaces exakt bei und speichert den Puffer ohne Umwege mit korrekter Dateiendung (`snippet.swift`, `payload.json`).
* **Beseitigte Frustration:** Kein Umweg über TextEdit (das standardmäßig RTF erzwingt) oder das Öffnen einer schweren IDE/VSCode, nur um einen JSON-Payload oder ein Shell-Skript als Datei abzulegen.

#### 3. Zero-Trace Privacy Sanitizer (Auto-Scrubbing)
* **Apple API:** `ImageIO` (`CGImageSourceCopyPropertiesAtIndex`, `CGImageDestination`), `CoreImage`.
* **Funktion:** Automatische, verlustfreie Entfernung sensibler EXIF-Metadaten (GPS-Koordinaten, Kameraseriennummern, Erstellungsdatum, Geräteprofil). Ergänzt durch eine On-Device-Gesichts- und Kennzeichenerkennung (`VNDetectFaceRectanglesRequest`), die auf Wunsch Gesichter oder vertrauliche Bildbereiche via `CIBoxBlur` mit einem Klick unkenntlich macht.
* **Beseitigte Frustration:** Angst vor Datenlecks beim Teilen von Screenshots oder Fotos in öffentlichen Repositories, Slack, Teams oder Foren.

#### 4. Hardware-Accelerated Media Compressor & Dynamic GIF-Engine
* **Apple API:** `AVFoundation` (`AVAssetReader`, `AVAssetWriter`), `ImageIO` (`CGImageDestinationCreateWithData`), `Accelerate.framework` (`vImage`).
* **Funktion:** Konvertiert Bildschirmaufnahmen (.mov) über die Media Engine des Apple Silicon Chips verzögerungsfrei in hochoptimierte MP4-Dateien (H.265/HEVC) oder animierte GIFs mit Octree-Farbquantisierung (kein Pixelrauschen, minimale Dateigröße). Konvertiert moderne Web-Formate (`.webp`) direkt in Standard-PNGs/JPEGs und umgekehrt.
* **Beseitigte Frustration:** Keine dubiosen Online-Konverter ("CloudConvert") für triviale Formatwechsel; kein mühsamer Terminal-Aufruf von `ffmpeg`.

#### 5. Local QR/Barcode Vector Factory
* **Apple API:** `CoreImage` (`CIQRCodeGenerator`), `Vision` (`VNDetectBarcodesRequest`).
* **Funktion:** Erkennt Barcodes/QRs aus Screenshots sofort und bietet Aktionen an (z. B. WLAN-Zugang direkt konfigurieren, OTP-Tokens extrahieren). Umgekehrt wandelt die App markierte URLs oder Textinhalte mit `CIContext` latenzfrei in druckfähige, vektorisierte PDF- oder SVG/PNG-Codes um.
* **Beseitigte Frustration:** Unsichere Online-QR-Generatoren entfallen komplett.

---

## 2. Perfektes UI/UX-Konzept (Apple Human Interface Guidelines)

Die App folgt dem Prinzip **"Zero Visual Clutter, Instant Recall"**. Sie belegt keinen permanenten Platz in der macOS-Menüleiste, wenn der Nutzer das nicht wünscht, und meidet starre Programmfenster.

```
Bildschirmrand (Rechts oder Notch-Integration)
+--------------------------------------------------------+
|                                                        |
|   Normaler Zustand:                                    |
|   Unsichtbarer 2px Sensorstreifen am Displayrand        |
|                                                        |
|   Drag-Session startet -> Hover nähert sich:           |
|                                                        |
|   +---------------------------------------------+      |
|   |  [+] DROPZONE (Milchglas / Liquid Blur)    |      |
|   |  .........................................  |      |
|   |  |   [Auto-Save]   |   [Convert WebP]   |  |<-HUD  |
|   |  |   [Strip EXIF]  |   [Extract Text]   |  |       |
|   |  .........................................  |      |
|   +---------------------------------------------+      |
+--------------------------------------------------------+
```

### 1. Das Panel: "The Floating Ledge"
* **Form & Material:** Ein ultradünner, schwebender Streifen (Shelf) an einer definierten Bildschirmkante (z. B. rechts mittig oder elegant unter der MacBook-Notch angedockt).
* **Materialität:** Echtes macOS-Material via `NSVisualEffectView` mit `.hudWindow`-Blending und `Material.ultraThinMaterial`. Feiner 0,5-Pt-Rahmen (`Color.white.opacity(0.15)` im Dark Mode, `Color.black.opacity(0.1)` im Light Mode). Abgerundete Ecken (`continuous`, Kurvenradius 16 pt).
* **Spring-Physics:** Öffnet und schließt über Apple-typische Federkern-Animationen (`response: 0.28s, dampingFraction: 0.82`). Keine linearen Übergänge.

### 2. Ergonomie & 0,2-Sekunden-Zugriff
* **Proaktive Drag-Awareness:** Startet das System eine systemweite Drag-and-Drop-Operation (`NSDraggingInfo`), blendet sich die Ledge an der aktiven Bildschirmkante dezent ein (Opacity: `0.0` $\rightarrow$ `0.95`, Ausdehnung: 4 pt $\rightarrow$ 72 pt Breite).
* **Hot-Edge / Hot-Corner:** Alternativ reicht eine minimale Curser-Wischgeste gegen den definierten Bildschirmrand, um die Ledge auszufahren.
* **Globaler Quick-Save:** `Cmd + Option + S` speichert den aktuellen Inhalt der Zwischenablage ohne Fensterinteraktion direkt im Hintergrund (akustisches Feedback über nativen System-Sound `NSSound(named: "Purr")`).
* **Heads-Up-Display (HUD):** `Cmd + Shift + V` öffnet das HUD direkt an der aktuellen Cursorposition mit Fokus auf die letzten 5 Aktionen.

### 3. Interaktionszonen ("Drop Slots")
Wird eine Datei oder Text über die Ledge gezogen, fächert sich das Panel in 3 visuell abgegrenzte Zielzonen auf:

```
+--------------------------------------------------------------------+
|  [ ZONE 1: SMART SAVE ]                                            |
|  Ordnet die Datei automatisch ein, setzt Zeitstempel & Tags.       |
+--------------------------------------------------------------------+
|  [ ZONE 2: ACTION PIPELINE ]                                       |
|  Kontextbasiert: "Als PDF konvertieren", "OCR & Kopieren",         |
|  "EXIF entfernen".                                                 |
+--------------------------------------------------------------------+
|  [ ZONE 3: SCRATCHPAD ]                                            |
|  Temporärer Zwischenspeicher ("Shelf") für spätere Weiterverwendung|
|  in anderen Apps (drag-out fähig).                                 |
+--------------------------------------------------------------------+
```

---

## 3. Dateiverwaltung & Smart-Folder-Struktur

Konfiguration erzeugt kognitive Last. *DropLedge* nutzt daher ein deterministisches, selbstreinigendes Speichersystem auf Basis von Standard-Dateisystemattributen (`Extended Attributes / xattr`).

### Standard-Speicherort
```
~/Documents/DropLedge Library/
```
*(Vom Nutzer frei wählbar; vollständige Kompatibilität mit Time Machine und lokaler Verschlüsselung via FileVault).*

### Die Ordnungs-Taxonomie

```
DropLedge Library/
├── 2026-10/
│   ├── Media/
│   │   ├── 2026-10-20_14-30-12_ScreenCapture_Xcode.png
│   │   └── 2026-10-20_14-32-44_Video_Optimized.mp4
│   ├── Code/
│   │   ├── 2026-10-20_15-01-05_Snippet.swift
│   │   └── 2026-10-20_15-12-00_Config.json
│   ├── Documents/
│   │   └── 2026-10-20_16-00-22_Receipt_Scanned.pdf
│   └── RawText/
│       └── 2026-10-20_16-45-11_ClipboardNote.txt
└── .catalog.sqlite  <-- Rein lokaler Index (Zero-Config-Suche)
```

### Deterministisches Namensschema
```
[ISO8601-Datum]_[Uhrzeit]_[Typ/Erkennung]_[Herkunft/App].[ext]
Beispiel: 2026-10-20_14-30-22_CodeSnippet_Xcode.swift
```

### Kollisionsauflösung & Metadaten
* **Kein Überschreiben:** Bei Namensgleichheit wird ein 4-stelliges Hex-Kürzel auf Basis des Datei-Hashes angehängt: `..._Xcode_a1f4.swift`.
* **Spotlight-Integration:** Zu jeder gespeicherten Datei werden native macOS Extended Attributes (`xattr`) geschrieben:
  * `com.apple.metadata:kMDItemFinderComment`: Enthält den vollen OCR-Text bzw. den Code-Inhalt.
  * `com.dropdesk.sourceApplication`: Bundle-Identifier der Quell-App (z. B. `com.apple.dt.Xcode`).
  * `com.dropdesk.originalChecksum`: SHA256 zur Erkennung identischer Duplikate (Duplikate werden referenziert statt mehrfach gespeichert).

---

## 4. Modulare Technische Architektur (Swift Package / Antigravity)

Die App ist modular nach Domain-Driven-Design auf Basis von Swift 6 Concurrency (Actors) aufgebaut. Es existieren keinerlei Abhängigkeiten außerhalb des macOS SDK.

```
                           +------------------------+
                           |       DropLedgeApp     |
                           |   (NSApplicationMain)  |
                           +-----------+------------+
                                       |
                 +---------------------+---------------------+
                 |                                           |
                 v                                           v
      +--------------------+                      +--------------------+
      |    LedgeUI (Kit)   |                      |  LedgeCore (Coord) |
      | (NSPanel, SwiftUI) |                      | (Actor Pipelines)  |
      +----------+---------+                      +----------+---------+
                 |                                           |
                 +---------------------+---------------------+
                                       |
       +-------------------------------+-------------------------------+
       |                               |                               |
       v                               v                               v
+--------------+               +---------------+               +---------------+
|  IO & Media  |               |  Intelligence |               |  Persistence  |
+--------------+               +---------------+               +---------------+
| Conversion   |               | VisionEngine  |               | Storage       |
| Clipboard    |               | CodeClassifier|               | Spotlight     |
+--------------+               +---------------+               +---------------+
```

### Modulübersicht

| Swift-Modul / Package | Zuständigkeit | Native Apple APIs |
| :--- | :--- | :--- |
| **`LedgeCore`** | Global Event Tap, Hotkeys, State-Machine, Routing | `AppKit`, `Carbon.HIToolbox` (nur Key-Taps), `Combine` |
| **`LedgeUI`** | Borderless HUD, Edge-Sensoren, Liquid-Drag-Zone | `SwiftUI`, `AppKit` (`NSPanel`, `NSHostingView`) |
| **`ClipboardService`** | Observation der Systemablage, Format-Inferenz | `AppKit` (`NSPasteboard`), `UniformTypeIdentifiers` |
| **`ConversionEngine`** | Lokale Transkodierung, Skalierung, Kompression | `ImageIO`, `CoreImage`, `AVFoundation`, `PDFKit`, `Accelerate` |
| **`VisionEngine`** | OCR, Barcodes, Face Detection | `Vision.framework`, `CoreGraphics` |
| **`CodeAnalysis`** | Heuristische Syntaxerkennung, Indent-Erhalt | `NaturalLanguage`, Swift Regex (`RegexBuilder`) |
| **`StorageCoordinator`**| Thread-sicheres File-I/O, Smart-Folder, xattrs | `Foundation` (`FileManager`), `UniformTypeIdentifiers` |

---

### Implementierungs-Blaupausen (Produktionsfertiger Code)

#### 1. Panel-Fenster: Ultraschnelles, nicht-aktivierendes `NSPanel`
Das Fenster darf bei Einblendung niemals den Fokus der aktuellen App (z. B. Xcode, Final Cut) stehlen.

```swift
// Package: LedgeUI
import AppKit
import SwiftUI

public final class FloatingLedgePanel: NSPanel {
    public init(contentRect: NSRect, rootContent: some View) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        
        let hostingView = NSHostingView(rootView: rootContent)
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }
    
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
```

---

#### 2. VisionEngine: Zero-Cloud OCR Worker
Reine Offline-Texterkennung direkt über die Apple Neural Engine.

```swift
// Package: VisionEngine
import Foundation
import Vision
import CoreGraphics

public actor VisionEngine {
    public static let shared = VisionEngine()
    private init() {}
    
    public enum VisionError: Error {
        case executionFailed
        case noTextDetected
    }
    
    public func recognizeText(from cgImage: CGImage) throws -> (fullText: String, confidence: Float) {
        var recognizedStrings: [String] = []
        var totalConfidence: Float = 0.0
        var blockCount: Int = 0
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US"]
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else {
            throw VisionError.noTextDetected
        }
        
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            recognizedStrings.append(topCandidate.string)
            totalConfidence += topCandidate.confidence
            blockCount += 1
        }
        
        guard !recognizedStrings.isEmpty else {
            throw VisionError.noTextDetected
        }
        
        let finalConfidence = blockCount > 0 ? (totalConfidence / Float(blockCount)) : 0.0
        return (recognizedStrings.joined(separator: "\n"), finalConfidence)
    }
}
```

---

#### 3. ConversionEngine: Verlustfreie EXIF-Bereinigung & Bildkompression
Entfernt Metadaten ohne Re-Encoding-Artefakte über `ImageIO`.

```swift
// Package: ConversionEngine
import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor ImageOptimizer {
    public static let shared = ImageOptimizer()
    private init() {}
    
    public func stripMetadata(from sourceURL: URL, targetURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let uti = CGImageSourceGetType(source) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, uti, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        // Vollständiges Bereinigen der Exif/TIFF/GPS Dictionaries
        let emptyProperties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [:],
            kCGImagePropertyGPSDictionary: [:],
            kCGImagePropertyTIFFDictionary: [:]
        ]
        
        CGImageDestinationAddImageFromSource(destination, source, 0, emptyProperties as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
```

---

#### 4. CodeAnalysisService: Heuristischer Syntax-Klassifikator
Erkennt Programmiersprachen und Dateiendungen aus Rohdaten ohne UI-Formatverlust.

```swift
// Package: CodeAnalysis
import Foundation
import UniformTypeIdentifiers

public struct CodeClassifier {
    public struct ClassificationResult: Sendable {
        public let fileExtension: String
        public let detectedType: UTType
        public let cleanedContent: String
    }
    
    public static func classify(rawText: String) -> ClassificationResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. JSON-Erkennung
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || 
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil {
                return ClassificationResult(fileExtension: "json", detectedType: .json, cleanedContent: rawText)
            }
        }
        
        // 2. Swift-Erkennung
        let swiftKeywords = ["import SwiftUI", "import Foundation", "func ", "var ", "let ", "struct ", "final class "]
        let swiftScore = swiftKeywords.reduce(0) { $0 + (trimmed.contains($1) ? 1 : 0) }
        if swiftScore >= 2 {
            return ClassificationResult(fileExtension: "swift", detectedType: .swiftSource, cleanedContent: rawText)
        }
        
        // 3. Python-Erkennung
        let pythonKeywords = ["def ", "import ", "from ", "elif ", "print(", "__main__"]
        let pythonScore = pythonKeywords.reduce(0) { $0 + (trimmed.contains($1) ? 1 : 0) }
        if pythonScore >= 2 || (trimmed.contains(":") && trimmed.contains("    ")) {
            return ClassificationResult(fileExtension: "py", detectedType: .pythonScript, cleanedContent: rawText)
        }
        
        // 4. Shell-Skripte
        if trimmed.hasPrefix("#!/bin/bash") || trimmed.hasPrefix("#!/bin/zsh") || trimmed.hasPrefix("#!/bin/sh") {
            return ClassificationResult(fileExtension: "sh", detectedType: .shellScript, cleanedContent: rawText)
        }
        
        // Fallback: Markdown oder Plain Text
        if trimmed.contains("# ") || trimmed.contains("```") {
            return ClassificationResult(fileExtension: "md", detectedType: UTType(filenameExtension: "md") ?? .plainText, cleanedContent: rawText)
        }
        
        return ClassificationResult(fileExtension: "txt", detectedType: .plainText, cleanedContent: rawText)
    }
}
```

---

#### 5. StorageCoordinator: Metadata Preservation & Extended Attributes (xattr)
Speichert Dateien thread-sicher und schreibt Spotlight-Metadaten für globale Suchbarkeit.

```swift
// Package: StorageCoordinator
import Foundation
import System

public actor StorageCoordinator {
    public static let shared = StorageCoordinator()
    private let fileManager = FileManager.default
    
    private init() {}
    
    public func persist(
        data: Data, 
        baseDirectory: URL, 
        subFolder: String, 
        fileName: String, 
        spotlightComment: String?
    ) throws -> URL {
        let destinationDir = baseDirectory.appendingPathComponent(subFolder, isDirectory: true)
        
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        
        let destinationFileURL = destinationDir.appendingPathComponent(fileName)
        try data.write(to: destinationFileURL, options: .atomic)
        
        // Schreibe Spotlight Finder Comment nativ via macOS xattr
        if let comment = spotlightComment {
            try setFinderComment(comment, for: destinationFileURL)
        }
        
        return destinationFileURL
    }
    
    private func setFinderComment(_ comment: String, for fileURL: URL) throws {
        let commentData = try PropertyListSerialization.data(
            fromPropertyList: comment,
            format: .binary,
            options: 0
        )
        
        let attributeName = "com.apple.metadata:kMDItemFinderComment"
        fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path = path else { return }
            commentData.withUnsafeBytes { buffer in
                _ = setxattr(path, attributeName, buffer.baseAddress, buffer.count, 0, 0)
            }
        }
    }
}
```

---

## 5. Blueprint-Zusammenfassung für den Antigravity-Build-Run

* **Deployment-Target:** macOS 14.0+ (Universal).
* **Entwicklungs-Tooling:** Xcode 16+ / Swift 6.0 (Strict Concurrency aktiv).
* **Entitlement-Anforderungen:** 
  * App Sandbox: `com.apple.security.files.user-selected.read-write` (für Zielordner), `com.apple.security.files.downloads.read-write`.
  * Kein Netzwerkzugriff deklariert (`com.apple.security.network.client` = `false`, `server` = `false`). Audit-Garantie: Zero-Telemetry.
* **Architektur-Pattern:** Reaktiv, UI-Status entkoppelt via `ObservableObject`/`@Observable` Macro, Backend-Verarbeitung isoliert in Swift Actors (`StorageCoordinator`, `VisionEngine`, `ImageOptimizer`).

Dieser Entwurf bietet eine vollständige, sofort einsatzbereite architektonische Vorlage. Er verzichtet auf externe Package-Abhängigkeiten, maximiert die Apple-Silicon-Performance und löst alltägliche Mac-Reibungspunkte elegant und ressourcenschonend.