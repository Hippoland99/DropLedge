import XCTest
import UniformTypeIdentifiers
@testable import CodeAnalysis

final class CodeClassifierTests: XCTestCase {
    
    func testJSONClassification() {
        let jsonObject = """
        {
            "name": "DropLedge",
            "offline": true,
            "version": 1.0
        }
        """
        let resultObj = CodeClassifier.classify(rawText: jsonObject)
        XCTAssertEqual(resultObj.fileExtension, "json")
        XCTAssertEqual(resultObj.detectedType, .json)
        XCTAssertEqual(resultObj.language, .json)
        
        let jsonArray = """
        [1, 2, 3, {"item": "macOS"}]
        """
        let resultArr = CodeClassifier.classify(rawText: jsonArray)
        XCTAssertEqual(resultArr.fileExtension, "json")
        XCTAssertEqual(resultArr.detectedType, .json)
        XCTAssertEqual(resultArr.language, .json)
    }
    
    func testSwiftClassification() {
        let swiftCode = """
        import SwiftUI
        
        public struct LedgeOverlay: View {
            public var body: some View {
                Text("DropLedge Active")
            }
        }
        """
        let result = CodeClassifier.classify(rawText: swiftCode)
        XCTAssertEqual(result.fileExtension, "swift")
        XCTAssertEqual(result.detectedType, .swiftSource)
        XCTAssertEqual(result.language, .swift)
    }
    
    func testPythonClassification() {
        let pythonCode = """
        import sys
        
        def process_items(items):
            for item in items:
                print(f"Processing {item}")
        """
        let result = CodeClassifier.classify(rawText: pythonCode)
        XCTAssertEqual(result.fileExtension, "py")
        XCTAssertEqual(result.detectedType, .pythonScript)
        XCTAssertEqual(result.language, .python)
        
        let pythonWithShebang = """
        #!/usr/bin/env python3
        print("Hello from Python")
        """
        let shebangResult = CodeClassifier.classify(rawText: pythonWithShebang)
        XCTAssertEqual(shebangResult.fileExtension, "py")
        XCTAssertEqual(shebangResult.detectedType, .pythonScript)
        XCTAssertEqual(shebangResult.language, .python)
    }
    
    func testShellClassification() {
        let zshScript = """
        #!/bin/zsh
        echo "Building DropLedge..."
        swift build -c release
        """
        let result = CodeClassifier.classify(rawText: zshScript)
        XCTAssertEqual(result.fileExtension, "sh")
        XCTAssertEqual(result.detectedType, .shellScript)
        XCTAssertEqual(result.language, .shell)
        
        let bashCommands = """
        chmod +x ./build.sh
        export PATH="/opt/homebrew/bin:$PATH"
        """
        let commandResult = CodeClassifier.classify(rawText: bashCommands)
        XCTAssertEqual(commandResult.fileExtension, "sh")
        XCTAssertEqual(commandResult.detectedType, .shellScript)
        XCTAssertEqual(commandResult.language, .shell)
    }
    
    func testMarkdownClassification() {
        let markdownDoc = """
        # DropLedge Feature List
        
        DropLedge ist ein natives Mac-Tool.
        
        ```swift
        let state = AppState.shared
        ```
        
        Weitere Infos unter [Dokumentation](https://dropledge.local).
        """
        let result = CodeClassifier.classify(rawText: markdownDoc)
        XCTAssertEqual(result.fileExtension, "md")
        XCTAssertEqual(result.language, .markdown)
    }
    
    func testCSVClassification() {
        let csvData = """
        name,age,country
        Alice,28,Germany
        Bob,34,Austria
        """
        let result = CodeClassifier.classify(rawText: csvData)
        XCTAssertEqual(result.fileExtension, "csv")
        XCTAssertEqual(result.language, .csv)
    }
    
    func testENVClassification() {
        let envData = """
        # Configuration
        DATABASE_URL=postgres://localhost:5432/app
        API_SECRET=super_secret_key_42
        PORT=8080
        """
        let result = CodeClassifier.classify(rawText: envData)
        XCTAssertEqual(result.fileExtension, "env")
        XCTAssertEqual(result.language, .env)
    }
    
    func testPlainTextFallback() {
        let plainText = """
        Einkaufsliste für das Wochenende:
        - Äpfel
        - Hafermilch
        - Kaffee
        """
        let result = CodeClassifier.classify(rawText: plainText)
        XCTAssertEqual(result.fileExtension, "txt")
        XCTAssertEqual(result.detectedType, .plainText)
        XCTAssertEqual(result.language, .plainText)
    }
}
