//
//  WorkspaceFile.swift
//  llmHub
//
//  Represents a file in the CloudWorkspace (code execution outputs, etc.)
//

import Foundation

/// Represents a file in the CloudWorkspace (code execution outputs, etc.)
struct WorkspaceFile: Identifiable, Equatable, Sendable {
    let id: String  // filename as ID (unique within workspace)
    let filename: String
    let sizeBytes: Int
    let modifiedAt: Date?
    let fileType: FileType
    
    enum FileType: String, CaseIterable, Sendable {
        case code       // .swift, .py, .js, etc.
        case output     // output_*.txt
        case error      // error_*.txt
        case image      // .png, .jpg, .svg
        case data       // .json, .csv
        case other
        
        var icon: String {
            switch self {
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .output: return "text.alignleft"
            case .error: return "exclamationmark.triangle"
            case .image: return "photo"
            case .data: return "tablecells"
            case .other: return "doc"
            }
        }
        
        var tintColor: String {
            switch self {
            case .code: return "accent"
            case .output: return "green"
            case .error: return "red"
            case .image: return "purple"
            case .data: return "blue"
            case .other: return "secondary"
            }
        }
    }
    
    static func detect(filename: String) -> FileType {
        let lower = filename.lowercased()
        
        // Output patterns from CodeInterpreterTool
        if lower.hasPrefix("output_") && lower.hasSuffix(".txt") { return .output }
        if lower.hasPrefix("error_") && lower.hasSuffix(".txt") { return .error }
        if lower.hasPrefix("code_") { return .code }
        
        // Extension-based
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "dart": return .code
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return .image
        case "json", "csv", "tsv": return .data
        case "txt": return .output  // Default txt to output
        default: return .other
        }
    }
}
