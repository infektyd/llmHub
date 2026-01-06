//
//  AppLogger.swift
//  llmHub
//
//  Minimal helper for consistent Logger creation.
//

import OSLog
import SwiftData

enum AppLogger {
    nonisolated static func category(_ category: String) -> Logger {
        Logger(subsystem: "com.llmhub", category: category)
    }
}
