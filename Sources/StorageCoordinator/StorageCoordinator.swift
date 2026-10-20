import Foundation
import System
import Darwin
import CryptoKit

public enum StorageCategory: String, Sendable, CaseIterable {
    case media = "Media"
    case code = "Code"
    case documents = "Documents"
    case rawText = "RawText"
}

public actor StorageCoordinator {
    public static let shared = StorageCoordinator()
    private let fileManager = FileManager.default
    
    public static let finderCommentAttribute = "com.apple.metadata:kMDItemFinderComment"
    public static let sourceAppAttribute = "com.dropdesk.sourceApplication"
    public static let checksumAttribute = "com.dropdesk.originalChecksum"
    
    private let yearMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
    
    private let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
    
    private init() {}
    
    /// Low-Level Persist-Methode mit Unterordner und Dateinamen
    public func persist(
        data: Data, 
        baseDirectory: URL, 
        subFolder: String, 
        fileName: String, 
        spotlightComment: String? = nil,
        sourceApplication: String? = nil
    ) throws -> URL {
        let destinationDir = baseDirectory.appendingPathComponent(subFolder, isDirectory: true)
        
        if !fileManager.fileExists(atPath: destinationDir.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        
        let destinationFileURL = resolveCollision(in: destinationDir, desiredFileName: fileName, data: data)
        try data.write(to: destinationFileURL, options: .atomic)
        
        // Schreibe Spotlight Finder Comment nativ via macOS xattr
        if let comment = spotlightComment {
            try setFinderComment(comment, for: destinationFileURL)
        }
        
        // Schreibe Quell-Applikation Metadaten
        if let sourceApp = sourceApplication {
            try setStringAttribute(name: Self.sourceAppAttribute, value: sourceApp, for: destinationFileURL)
        }
        
        // Schreibe SHA256 Prüfsumme
        let checksum = calculateSHA256(for: data)
        try setStringAttribute(name: Self.checksumAttribute, value: checksum, for: destinationFileURL)
        
        return destinationFileURL
    }
    
    /// High-Level Persist-Methode basierend auf der Taxonomie aus ARCHITECTURE.md
    /// Schema: BaseDirectory/YYYY-MM/Category/[ISO8601-Datum]_[Uhrzeit]_[Typ/Erkennung]_[Herkunft/App].[ext]
    public func persistCategorized(
        data: Data,
        baseDirectory: URL,
        category: StorageCategory,
        typeName: String,
        sourceApp: String? = nil,
        fileExtension: String,
        spotlightComment: String? = nil,
        date: Date = Date()
    ) throws -> URL {
        let yearMonth = yearMonthFormatter.string(from: date)
        let subFolder = "\(yearMonth)/\(category.rawValue)"
        
        let timestamp = isoDateFormatter.string(from: date)
        let sanitizedType = typeName.replacingOccurrences(of: " ", with: "")
        let sanitizedApp = (sourceApp ?? "Clipboard").replacingOccurrences(of: " ", with: "")
        let cleanExt = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        
        let fileName = "\(timestamp)_\(sanitizedType)_\(sanitizedApp).\(cleanExt)"
        
        return try persist(
            data: data,
            baseDirectory: baseDirectory,
            subFolder: subFolder,
            fileName: fileName,
            spotlightComment: spotlightComment,
            sourceApplication: sourceApp
        )
    }
    
    // MARK: - Collision Resolution
    
    private func resolveCollision(in directory: URL, desiredFileName: String, data: Data) -> URL {
        let initialURL = directory.appendingPathComponent(desiredFileName)
        if !fileManager.fileExists(atPath: initialURL.path(percentEncoded: false)) {
            return initialURL
        }
        
        let ext = initialURL.pathExtension
        let nameWithoutExt = initialURL.deletingPathExtension().lastPathComponent
        let checksum = calculateSHA256(for: data)
        let shortHash = String(checksum.prefix(4))
        
        let uniqueName = ext.isEmpty ? "\(nameWithoutExt)_\(shortHash)" : "\(nameWithoutExt)_\(shortHash).\(ext)"
        let candidateURL = directory.appendingPathComponent(uniqueName)
        
        if !fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) {
            return candidateURL
        }
        
        // Fallback für identischen Hash & Namen
        let fullHashPrefix = String(checksum.prefix(8))
        let finalName = ext.isEmpty ? "\(nameWithoutExt)_\(fullHashPrefix)" : "\(nameWithoutExt)_\(fullHashPrefix).\(ext)"
        return directory.appendingPathComponent(finalName)
    }
    
    // MARK: - SHA256 Checksum
    
    public func calculateSHA256(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Extended Attributes (xattr)
    
    public func setFinderComment(_ comment: String, for fileURL: URL) throws {
        let commentData = try PropertyListSerialization.data(
            fromPropertyList: comment,
            format: .binary,
            options: 0
        )
        try setExtendedAttribute(name: Self.finderCommentAttribute, value: commentData, for: fileURL)
    }
    
    public func getFinderComment(for fileURL: URL) throws -> String? {
        guard let data = try getExtendedAttribute(name: Self.finderCommentAttribute, for: fileURL) else {
            return nil
        }
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plistObj = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        return plistObj as? String
    }
    
    public func setStringAttribute(name: String, value: String, for fileURL: URL) throws {
        guard let data = value.data(using: .utf8) else { return }
        try setExtendedAttribute(name: name, value: data, for: fileURL)
    }
    
    public func getStringAttribute(name: String, for fileURL: URL) throws -> String? {
        guard let data = try getExtendedAttribute(name: name, for: fileURL) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    public func setExtendedAttribute(name: String, value: Data, for fileURL: URL) throws {
        let status = fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path = path else { return -1 }
            return value.withUnsafeBytes { buffer in
                setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0)
            }
        }
        if status != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    
    public func getExtendedAttribute(name: String, for fileURL: URL) throws -> Data? {
        let size = fileURL.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path = path else { return -1 }
            return getxattr(path, name, nil, 0, 0, 0)
        }
        guard size >= 0 else {
            if errno == ENOATTR { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var data = Data(count: size)
        let readResult = data.withUnsafeMutableBytes { buffer -> Int in
            fileURL.withUnsafeFileSystemRepresentation { path -> Int in
                guard let path = path else { return -1 }
                return getxattr(path, name, buffer.baseAddress, size, 0, 0)
            }
        }
        guard readResult >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return data
    }
}
