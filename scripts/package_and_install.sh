#!/bin/bash
set -e

APP_NAME="DropLedge"
APP_BUNDLE="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BINARY_SOURCE=".build/release/DropLedgeApp"

echo "=== Building & Installing ${APP_NAME}.app to /Applications ==="

# 1. Sicherstellen, dass das Release-Binary existiert
if [ ! -f "$BINARY_SOURCE" ]; then
    echo "Kompiliere Release-Binary..."
    swift build -c release
fi

# 2. Bestehende App beenden & Verzeichnis vorbereiten
pkill -f "DropLedgeApp" || true
sleep 0.5
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Binary kopieren
cp "$BINARY_SOURCE" "${MACOS_DIR}/DropLedgeApp"
chmod +x "${MACOS_DIR}/DropLedgeApp"

# 4. AppIcon kopieren
if [ -f "/tmp/AppIcon.icns" ]; then
    cp "/tmp/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 5. Info.plist schreiben
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DropLedgeApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.dropledge.app</string>
    <key>CFBundleName</key>
    <string>DropLedge</string>
    <key>CFBundleDisplayName</key>
    <string>DropLedge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>DropLedge benötigt Bildschirmaufnahme für Screenshots und OCR.</string>
</dict>
</plist>
EOF

# 6. Ad-hoc Signieren
codesign --force --deep --sign - "$APP_BUNDLE"

# 7. LaunchAgent (Autostart) einrichten
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
PLIST_FILE="${LAUNCH_AGENT_DIR}/com.dropledge.app.plist"
mkdir -p "$LAUNCH_AGENT_DIR"

cat << EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dropledge.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>${MACOS_DIR}/DropLedgeApp</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

# 8. LaunchAgent bei launchctl registrieren
UID_NUM=$(id -u)
launchctl bootout "gui/${UID_NUM}" "$PLIST_FILE" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$PLIST_FILE" 2>/dev/null || launchctl load -w "$PLIST_FILE" 2>/dev/null || true

echo "=== DropLedge erfolgreich in /Applications installiert & Autostart aktiviert! ==="
