# 📥 DropLedge

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0%20Strict%20Concurrency-F05138?style=flat-square&logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/Dependencies-0%20(Pure%20Native)-success?style=flat-square" alt="Zero Dependencies">
  <img src="https://img.shields.io/badge/Privacy-100%25%20Offline-blue?style=flat-square" alt="100% Offline">
  <img src="https://img.shields.io/badge/License-MIT-purple?style=flat-square" alt="License">
</p>

**DropLedge** is an ultra-fast, native macOS menu bar drop shelf, omni-converter, PDF studio, and instant OCR companion. Built exclusively with Swift, SwiftUI, AppKit, and Apple's native frameworks, DropLedge eliminates bloated Electron apps, sketchy cloud converters, and clumsy Terminal commands.

---

## ✨ Highlights

- 🗂️ **Zero-Friction Drop Shelf:** Drop files directly onto the menu bar icon or into the liquid-glass popover.
- 🔄 **OmniConverter Engine:** Convert images (WebP, PNG, JPEG, HEIC), videos (H.264 MP4, 15 FPS animated GIF, < 25 MB compression), and custom formats 100% locally.
- 📄 **PDF Studio:** True downscaled PDF compression (150 DPI / 72 DPI), page-range extraction (`"1, 3-5, 7"`), and 1-click first page extraction with before/after size savings badges.
- 📸 **Screenshot & Vision OCR Studio:** Press `Cmd + Shift + X` to capture any screen region and instantly extract text via Apple's Vision Neural Engine.
- 📝 **Text & Code Snippet Studio:** Press `Cmd + V` to ingest code or text from clipboard with automated syntax detection (`.json`, `.swift`, `.py`, `.md`, `.sh`, `.csv`, `.env`).
- 📳 **HapticAudioEngine:** Apple-grade trackpad alignment haptics (`NSHapticFeedbackManager`) synchronized with native macOS system sounds (`Pop`, `Tink`, `Bottle`, `Basso`, `Hero`, `Morse`).
- 🚀 **True Drag-Out Scratchpad:** Drag saved items back out into Finder, Mail, Slack, or web browsers with guaranteed original filename retention.
- 📌 **Pinnable Popover:** Toggle pin mode to keep DropLedge floating while multi-tasking across different workspaces.
- 🔒 **100% Offline & Private:** Zero network permissions, zero analytics, zero external dependencies.

---

## ⌨️ Shortcuts & Hotkeys

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Cmd + Shift + D` | **Toggle Popover** | Opens or hides the DropLedge shelf directly below the menu bar icon |
| `Cmd + Option + S` | **Quick Save** | Instantly saves current clipboard content into DropLedge Library |
| `Cmd + Shift + X` | **Screenshot & OCR** | Captures screen selection, triggers Vision OCR, and presents quick actions |
| `Cmd + V` | **Paste Snippet** | Ingests text into the Text & Code Studio when the popover is focused |

---

## 🛠️ Architecture & Technologies

DropLedge is architected as a modular Swift Package with strict Swift 6 concurrency separation:

```
┌────────────────────────────────────────────────────────┐
│                      DropLedgeApp                      │
│      (NSApplication, MenuBarController, Hotkeys)       │
├──────────────────────────┬─────────────────────────────┤
│         LedgeUI          │          LedgeCore          │
│  (SwiftUI Popover View,  │  (LedgeCoordinator,         │
│   Scratchpad, Actions,   │   HapticAudioEngine,        │
│   Liquid-Glass Styling)  │   ScreenshotStudio)         │
├──────────────────────────┴─────────────────────────────┤
│                   Hardware Engines                     │
│  ┌─────────────────────────┬─────────────────────────┐ │
│  │    ConversionEngine     │      VisionEngine       │ │
│  │ (ImageIO, AVFoundation, │    (Apple Vision,       │ │
│  │  PDFKit, CoreGraphics)  │   VNRecognizeText)      │ │
│  ├─────────────────────────┼─────────────────────────┤ │
│  │   StorageCoordinator    │      CodeClassifier     │ │
│  │ (Atomic FS, Taxonomy,   │ (Syntax & Heuristics,   │ │
│  │  Spotlight Metadata)    │  UTType Identification) │ │
│  └─────────────────────────┴─────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

For complete technical specifications and internal pipeline documentation, see [`ARCHITECTURE.md`](file:///Users/hippoland99/Documents/DropLedge/ARCHITECTURE.md).

---

## 📦 Requirements & Building

### Requirements
- macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- Apple Silicon (M1/M2/M3/M4) or Intel Mac
- Swift 6.0+ toolchain (Xcode 16+)

### Build & Run from Terminal

```bash
# Clone the repository
git clone https://github.com/Hippoland99/DropLedge.git
cd DropLedge

# Run unit tests (33 tests)
swift test

# Build debug binary
swift build

# Build optimized release binary
swift build -c release

# Run DropLedge
.build/release/DropLedgeApp
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
