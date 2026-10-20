import Foundation
import UniformTypeIdentifiers

public enum CodeLanguage: String, Sendable, CaseIterable, Equatable {
    case json = "JSON"
    case swift = "Swift"
    case python = "Python"
    case shell = "Shell"
    case markdown = "Markdown"
    case csv = "CSV"
    case env = "ENV"
    case plainText = "Plain Text"
    
    public init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "json": self = .json
        case "swift": self = .swift
        case "py": self = .python
        case "sh": self = .shell
        case "md": self = .markdown
        case "csv": self = .csv
        case "env": self = .env
        default: self = .plainText
        }
    }
}

public struct CodeClassifier: Sendable {
    public struct ClassificationResult: Sendable, Equatable {
        public let fileExtension: String
        public let detectedType: UTType
        public let language: CodeLanguage
        public let cleanedContent: String
        
        public init(
            fileExtension: String, 
            detectedType: UTType, 
            language: CodeLanguage, 
            cleanedContent: String
        ) {
            self.fileExtension = fileExtension
            self.detectedType = detectedType
            self.language = language
            self.cleanedContent = cleanedContent
        }
        
        public init(fileExtension: String, detectedType: UTType, cleanedContent: String) {
            self.init(
                fileExtension: fileExtension,
                detectedType: detectedType,
                language: CodeLanguage(fileExtension: fileExtension),
                cleanedContent: cleanedContent
            )
        }
    }
    
    public static func classify(rawText: String) -> ClassificationResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ClassificationResult(
                fileExtension: "txt",
                detectedType: .plainText,
                language: .plainText,
                cleanedContent: rawText
            )
        }
        
        // 1. JSON-Erkennung (sowohl Objekte {...} als auch Arrays [...])
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || 
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil {
                return ClassificationResult(
                    fileExtension: "json",
                    detectedType: .json,
                    language: .json,
                    cleanedContent: rawText
                )
            }
        }
        
        // 2. Shell-Erkennung (Shebang hat höchste Priorität)
        if trimmed.hasPrefix("#!/bin/bash") || trimmed.hasPrefix("#!/bin/zsh") || trimmed.hasPrefix("#!/bin/sh") ||
           trimmed.hasPrefix("#!/usr/bin/env bash") || trimmed.hasPrefix("#!/usr/bin/env zsh") || trimmed.hasPrefix("#!/usr/bin/env sh") {
            return ClassificationResult(
                fileExtension: "sh",
                detectedType: .shellScript,
                language: .shell,
                cleanedContent: rawText
            )
        }
        
        // 3. Python-Erkennung (Shebang oder Syntaxmuster)
        if trimmed.hasPrefix("#!/usr/bin/env python") || trimmed.hasPrefix("#!/usr/bin/python") {
            return ClassificationResult(
                fileExtension: "py",
                detectedType: .pythonScript,
                language: .python,
                cleanedContent: rawText
            )
        }
        
        let pythonKeywords = ["def ", "import ", "from ", "elif ", "print(", "__main__", "class ", "except:", "raise "]
        let pythonScore = pythonKeywords.reduce(0) { $0 + (trimmed.contains($1) ? 1 : 0) }
        let hasPythonIndentation = trimmed.contains(":\n    ") || trimmed.contains(":\r\n    ")
        if (pythonScore >= 2 && !trimmed.contains("func ") && !trimmed.contains("var ")) || (hasPythonIndentation && pythonScore >= 1) {
            return ClassificationResult(
                fileExtension: "py",
                detectedType: .pythonScript,
                language: .python,
                cleanedContent: rawText
            )
        }
        
        // 4. Swift-Erkennung
        let swiftKeywords = [
            "import SwiftUI", "import Foundation", "import AppKit", "func ", "var ",
            "let ", "struct ", "final class ", "actor ", "@MainActor", "protocol ",
            "public struct ", "private let "
        ]
        let swiftScore = swiftKeywords.reduce(0) { $0 + (trimmed.contains($1) ? 1 : 0) }
        let hasSwiftImport = trimmed.contains("import SwiftUI") || trimmed.contains("import Foundation") || trimmed.contains("import AppKit")
        if swiftScore >= 2 || hasSwiftImport {
            return ClassificationResult(
                fileExtension: "swift",
                detectedType: .swiftSource,
                language: .swift,
                cleanedContent: rawText
            )
        }
        
        // 5. Shell-Erkennung ohne Shebang (Heuristik für typische Befehle)
        let shellCommands = ["chmod +x ", "export PATH=", "grep -", "echo \"", "set -e\n", "sudo apt", "sudo brew", "npm install", "git commit"]
        let shellScore = shellCommands.reduce(0) { $0 + (trimmed.contains($1) ? 1 : 0) }
        if shellScore >= 2 {
            return ClassificationResult(
                fileExtension: "sh",
                detectedType: .shellScript,
                language: .shell,
                cleanedContent: rawText
            )
        }
        
        // 6. ENV-Erkennung (Mindestens 1 KEY=VALUE Zeile und hohe Quote an Assignments/Kommentaren)
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let assignmentLines = lines.filter { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            return !l.hasPrefix("#") && l.contains("=") && !l.hasPrefix("//") && !l.contains(" ") && !l.hasPrefix("<")
        }
        let envMatches = lines.filter { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            return l.hasPrefix("#") || (l.contains("=") && !l.hasPrefix("//") && !l.contains(" ") && !l.hasPrefix("<"))
        }
        if !assignmentLines.isEmpty && lines.count >= 2 && Double(envMatches.count) / Double(lines.count) >= 0.75 {
            return ClassificationResult(
                fileExtension: "env",
                detectedType: UTType(filenameExtension: "env") ?? .plainText,
                language: .env,
                cleanedContent: rawText
            )
        }
        
        // 7. CSV-Erkennung (Mindestens 2 Zeilen mit gleicher Komma- oder Semikolon-Anzahl)
        if lines.count >= 2 {
            let commaCounts = lines.map { $0.filter { $0 == "," }.count }
            let semicolonCounts = lines.map { $0.filter { $0 == ";" }.count }
            if let firstComma = commaCounts.first, firstComma >= 1, commaCounts.allSatisfy({ $0 == firstComma }) {
                return ClassificationResult(
                    fileExtension: "csv",
                    detectedType: UTType.commaSeparatedText,
                    language: .csv,
                    cleanedContent: rawText
                )
            } else if let firstSemi = semicolonCounts.first, firstSemi >= 1, semicolonCounts.allSatisfy({ $0 == firstSemi }) {
                return ClassificationResult(
                    fileExtension: "csv",
                    detectedType: UTType.commaSeparatedText,
                    language: .csv,
                    cleanedContent: rawText
                )
            }
        }
        
        // 8. Markdown-Erkennung (Überschriften, Fenced Code Blocks, Links)
        let hasMarkdownHeadings = trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") ||
                                  trimmed.contains("\n# ") || trimmed.contains("\n## ") || trimmed.contains("\n### ")
        let hasCodeBlock = trimmed.contains("```")
        let hasMarkdownLink = trimmed.contains("](") && trimmed.contains("[")
        if hasMarkdownHeadings || hasCodeBlock || hasMarkdownLink {
            return ClassificationResult(
                fileExtension: "md",
                detectedType: UTType(filenameExtension: "md") ?? .plainText,
                language: .markdown,
                cleanedContent: rawText
            )
        }
        
        // 9. Fallback: Plain Text
        return ClassificationResult(
            fileExtension: "txt",
            detectedType: .plainText,
            language: .plainText,
            cleanedContent: rawText
        )
    }
}
