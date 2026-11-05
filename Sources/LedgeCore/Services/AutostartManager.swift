import Foundation
import Combine
import AppKit
import ServiceManagement

@MainActor
public final class AutostartManager: ObservableObject {
    public static let shared = AutostartManager()
    
    public let agentLabel = "com.dropledge.app"
    public let installedAppPath = "/Applications/DropLedge.app"
    public let installedAppExecutable = "/Applications/DropLedge.app/Contents/MacOS/DropLedgeApp"
    
    public var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }
    
    public var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(agentLabel).plist")
    }
    
    @Published public private(set) var isAutostartEnabled: Bool = false
    
    private init() {
        checkStatus()
    }
    
    public func checkStatus() {
        let plistExists = FileManager.default.fileExists(atPath: plistURL.path)
        if #available(macOS 13.0, *) {
            let smEnabled = SMAppService.mainApp.status == .enabled
            isAutostartEnabled = plistExists || smEnabled
        } else {
            isAutostartEnabled = plistExists
        }
    }
    
    @discardableResult
    public func enableAutostart() -> Bool {
        var success = false
        
        // 1. Modernes macOS 13+ SMAppService
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                success = true
            } catch {
                // Kein Blocker, wenn App nicht gebündelt ausgeführt wird
            }
        }
        
        // 2. macOS System Events Login Item
        if FileManager.default.fileExists(atPath: installedAppPath) {
            let appleScript = """
            tell application "System Events"
                if not (exists (login item "DropLedge")) then
                    make login item at end with properties {path:"\(installedAppPath)", hidden:false, name:"DropLedge"}
                end if
            end tell
            """
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: appleScript) {
                script.executeAndReturnError(&errorInfo)
                if errorInfo == nil {
                    success = true
                }
            }
        }
        
        // 3. LaunchAgent Plist Fallback (funktioniert immer)
        do {
            try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            
            let executablePath: String
            if FileManager.default.fileExists(atPath: installedAppExecutable) {
                executablePath = installedAppExecutable
            } else if let mainExec = Bundle.main.executablePath, !mainExec.isEmpty {
                executablePath = mainExec
            } else {
                executablePath = installedAppExecutable
            }
            
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(agentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(executablePath)</string>
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
            """
            
            try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            success = true
        } catch {
            print("[DropLedge AutostartManager] LaunchAgent write error: \(error)")
        }
        
        checkStatus()
        return success
    }
    
    @discardableResult
    public func disableAutostart() -> Bool {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
        
        let appleScript = """
        tell application "System Events"
            if exists (login item "DropLedge") then
                delete login item "DropLedge"
            end if
        end tell
        """
        if let script = NSAppleScript(source: appleScript) {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
        }
        
        try? FileManager.default.removeItem(at: plistURL)
        checkStatus()
        return true
    }
    
    public func toggleAutostart() {
        if isAutostartEnabled {
            disableAutostart()
        } else {
            enableAutostart()
        }
    }
}
