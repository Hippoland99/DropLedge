import XCTest
@testable import StorageCoordinator

final class StorageCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("StorageCoordinatorTests_\(uniqueID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }
    
    func testAtomicPersistAndSpotlightFinderComment() async throws {
        let coordinator = StorageCoordinator.shared
        let payload = "print('Hello DropLedge!')".data(using: .utf8)!
        let commentText = "Spotlight OCR Content: Full Python script"
        
        let savedURL = try await coordinator.persist(
            data: payload,
            baseDirectory: tempDirectory,
            subFolder: "2026-10/Code",
            fileName: "TestScript.py",
            spotlightComment: commentText,
            sourceApplication: "com.apple.dt.Xcode"
        )
        
        // 1. Datei existiert und Inhalt stimmt überein
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path(percentEncoded: false)))
        let savedData = try Data(contentsOf: savedURL)
        XCTAssertEqual(savedData, payload)
        
        // 2. Spotlight Finder Comment via xattr (kMDItemFinderComment) verifizieren
        let readComment = try await coordinator.getFinderComment(for: savedURL)
        XCTAssertEqual(readComment, commentText)
        
        // 3. Quell-Applikation und SHA256 Prüfsumme verifizieren
        let sourceApp = try await coordinator.getStringAttribute(name: StorageCoordinator.sourceAppAttribute, for: savedURL)
        XCTAssertEqual(sourceApp, "com.apple.dt.Xcode")
        
        let checksum = try await coordinator.getStringAttribute(name: StorageCoordinator.checksumAttribute, for: savedURL)
        let expectedChecksum = await coordinator.calculateSHA256(for: payload)
        XCTAssertEqual(checksum, expectedChecksum)
    }
    
    func testTaxonomyAndCollisionResolution() async throws {
        let coordinator = StorageCoordinator.shared
        let payloadA = "First content".data(using: .utf8)!
        let payloadB = "Second content differing".data(using: .utf8)!
        
        let fixedDate = Date(timeIntervalSince1970: 1792461600) // 2026-10-20
        
        let url1 = try await coordinator.persistCategorized(
            data: payloadA,
            baseDirectory: tempDirectory,
            category: .code,
            typeName: "Snippet",
            sourceApp: "Xcode",
            fileExtension: "swift",
            spotlightComment: "Snippet A",
            date: fixedDate
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: url1.path(percentEncoded: false)))
        XCTAssertTrue(url1.path.contains("2026-10/Code"))
        
        // Zweiter Speichervorgang zum identischen Zeitpunkt -> Kollisionsauflösung mit 4-stelligem Hash
        let url2 = try await coordinator.persistCategorized(
            data: payloadB,
            baseDirectory: tempDirectory,
            category: .code,
            typeName: "Snippet",
            sourceApp: "Xcode",
            fileExtension: "swift",
            spotlightComment: "Snippet B",
            date: fixedDate
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: url2.path(percentEncoded: false)))
        XCTAssertNotEqual(url1.path, url2.path)
        
        // Überprüfen, dass die kollidierte Datei den 4-stelligen SHA256-Präfix enthält
        let expectedHash = await coordinator.calculateSHA256(for: payloadB)
        let shortHash = String(expectedHash.prefix(4))
        XCTAssertTrue(url2.lastPathComponent.contains(shortHash))
    }
}
