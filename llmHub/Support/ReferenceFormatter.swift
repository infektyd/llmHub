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
}
