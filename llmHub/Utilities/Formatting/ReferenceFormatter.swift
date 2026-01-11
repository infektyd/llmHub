//
//  ReferenceFormatter.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation

enum ReferenceFormatter {
    static func newReferenceID(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd"
        let dateString = formatter.string(from: date)
        let random = Int.random(in: 1...999).formatted(.number.precision(.fractionLength(3)))
        return "chat_\(dateString)_\(random)"
    }

    static func formatForRequest(_ references: [ChatReference]) -> String {
        guard !references.isEmpty else { return "" }

        var lines: [String] = ["<references>"]
        for ref in references {
            lines.append("[\(ref.role.rawValue)]")
            lines.append(ref.text)
            lines.append("---")
        }
        if lines.last == "---" {
            lines.removeLast()
        }
        lines.append("</references>")
        return lines.joined(separator: "\n")
    }
}
