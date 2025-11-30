//
//  FileReaderTool.swift
//  llmHub
//
//  File reading tool for analyzing documents and files
//

import Foundation
import OSLog
import UniformTypeIdentifiers
import PDFKit

/// File Reader Tool conforming to the Tool protocol
/// Reads and extracts content from various file types
struct FileReaderTool: Tool {
    let id = "read_file"
    let name = "read_file"
    let description = """
        Read and analyze the contents of files. \
        Supports text files (txt, md, json, xml, csv), \
        PDF documents, and can describe images. \
        Use this when you need to examine file contents or analyze documents.
        """
    
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The file path to read. Can be absolute or relative to the working directory."
                ],
                "encoding": [
                    "type": "string",
                    "description": "Text encoding (default: utf-8). Options: utf-8, ascii, utf-16"
                ],
                "max_length": [
                    "type": "integer",
                    "description": "Maximum number of characters to return (default: 50000)"
                ]
            ],
            "required": ["path"]
        ]
    }
    
    private let logger = Logger(subsystem: "com.llmhub", category: "FileReaderTool")
    private let maxDefaultLength = 50000
    
    func execute(input: [String: Any]) async throws -> String {
        guard let path = input["path"] as? String, !path.isEmpty else {
            throw ToolError.invalidInput
        }
        
        let maxLength = input["max_length"] as? Int ?? maxDefaultLength
        let encodingName = input["encoding"] as? String ?? "utf-8"
        
        let encoding: String.Encoding = {
            switch encodingName.lowercased() {
            case "ascii": return .ascii
            case "utf-16": return .utf16
            default: return .utf8
            }
        }()
        
        // Resolve path
        let fileURL: URL
        if path.hasPrefix("/") || path.hasPrefix("~") {
            fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            // Relative to working directory
            fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }
        
        logger.info("Reading file: \(fileURL.path)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileReaderError.fileNotFound(path)
        }
        
        // Determine file type and read accordingly
        let fileExtension = fileURL.pathExtension.lowercased()
        
        do {
            let content: String
            
            switch fileExtension {
            case "pdf":
                content = try readPDF(url: fileURL, maxLength: maxLength)
            case "json":
                content = try readJSON(url: fileURL, maxLength: maxLength)
            case "csv":
                content = try readCSV(url: fileURL, maxLength: maxLength)
            case "png", "jpg", "jpeg", "gif", "webp", "heic":
                content = try describeImage(url: fileURL)
            case "rtf":
                content = try readRTF(url: fileURL, maxLength: maxLength)
            default:
                // Try as plain text
                content = try readText(url: fileURL, encoding: encoding, maxLength: maxLength)
            }
            
            return formatFileContent(path: path, content: content, truncated: content.count >= maxLength)
            
        } catch let error as FileReaderError {
            throw ToolError.executionFailed(error.localizedDescription)
        } catch {
            logger.error("Failed to read file: \(error)")
            throw ToolError.executionFailed("Failed to read file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File Readers
    
    private func readText(url: URL, encoding: String.Encoding, maxLength: Int) throws -> String {
        let content = try String(contentsOf: url, encoding: encoding)
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "\n\n[Content truncated at \(maxLength) characters]"
        }
        return content
    }
    
    private func readJSON(url: URL, maxLength: Int) throws -> String {
        let data = try Data(contentsOf: url)
        
        // Pretty-print JSON
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            
            if prettyString.count > maxLength {
                return String(prettyString.prefix(maxLength)) + "\n\n[JSON truncated at \(maxLength) characters]"
            }
            return prettyString
        }
        
        // Fallback to raw content
        return try readText(url: url, encoding: .utf8, maxLength: maxLength)
    }
    
    private func readCSV(url: URL, maxLength: Int) throws -> String {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var output = "CSV File Analysis:\n"
        output += "Total lines: \(lines.count)\n"
        
        if let header = lines.first {
            let columns = header.components(separatedBy: ",")
            output += "Columns: \(columns.count)\n"
            output += "Headers: \(columns.joined(separator: " | "))\n"
        }
        
        output += "\nContent:\n"
        output += String(repeating: "-", count: 50) + "\n"
        
        // Add first N rows
        let rowsToShow = min(lines.count, 100)
        let csvContent = lines.prefix(rowsToShow).joined(separator: "\n")
        
        if csvContent.count > maxLength {
            output += String(csvContent.prefix(maxLength))
            output += "\n\n[CSV truncated. Showing \(rowsToShow) of \(lines.count) rows]"
        } else {
            output += csvContent
            if lines.count > rowsToShow {
                output += "\n\n[Showing first \(rowsToShow) of \(lines.count) rows]"
            }
        }
        
        return output
    }
    
    private func readPDF(url: URL, maxLength: Int) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw FileReaderError.invalidFormat("Could not open PDF document")
        }
        
        var output = "PDF Document Analysis:\n"
        output += "Pages: \(document.pageCount)\n"
        
        if let metadata = document.documentAttributes {
            if let title = metadata[PDFDocumentAttribute.titleAttribute] as? String {
                output += "Title: \(title)\n"
            }
            if let author = metadata[PDFDocumentAttribute.authorAttribute] as? String {
                output += "Author: \(author)\n"
            }
        }
        
        output += "\nExtracted Text:\n"
        output += String(repeating: "-", count: 50) + "\n"
        
        var extractedText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let pageText = page.string {
                extractedText += "--- Page \(i + 1) ---\n"
                extractedText += pageText + "\n"
            }
            
            // Check length periodically
            if extractedText.count > maxLength {
                break
            }
        }
        
        if extractedText.count > maxLength {
            output += String(extractedText.prefix(maxLength))
            output += "\n\n[PDF content truncated at \(maxLength) characters]"
        } else {
            output += extractedText
        }
        
        return output
    }
    
    private func readRTF(url: URL, maxLength: Int) throws -> String {
        let data = try Data(contentsOf: url)
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        
        let attributed = try NSAttributedString(data: data, options: options, documentAttributes: nil)
        let content = attributed.string
        
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "\n\n[RTF content truncated at \(maxLength) characters]"
        }
        
        return content
    }
    
    private func describeImage(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        
        var output = "Image File:\n"
        output += "Path: \(url.lastPathComponent)\n"
        output += "Size: \(fileSize)\n"
        output += "Format: \(url.pathExtension.uppercased())\n"
        
        // Try to get image dimensions
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                output += "Dimensions: \(width) × \(height) pixels\n"
            }
        }
        
        // Provide base64 for small images (under 100KB)
        if data.count < 100_000 {
            let base64 = data.base64EncodedString()
            output += "\nBase64 Data (for analysis):\n"
            output += "data:image/\(url.pathExtension.lowercased());base64,\(base64.prefix(500))...\n"
            output += "[Full base64 available - \(base64.count) characters]"
        } else {
            output += "\n[Image too large for inline base64 - \(fileSize)]"
        }
        
        return output
    }
    
    // MARK: - Formatting
    
    private func formatFileContent(path: String, content: String, truncated: Bool) -> String {
        var output = "File: \(path)\n"
        output += String(repeating: "=", count: 50) + "\n\n"
        output += content
        return output
    }
}

// MARK: - Errors

enum FileReaderError: LocalizedError {
    case fileNotFound(String)
    case invalidFormat(String)
    case accessDenied(String)
    case readError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .invalidFormat(let reason): return "Invalid file format: \(reason)"
        case .accessDenied(let path): return "Access denied: \(path)"
        case .readError(let reason): return "Read error: \(reason)"
        }
    }
}

