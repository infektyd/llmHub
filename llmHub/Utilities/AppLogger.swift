//
//  AppLogger.swift
//  llmHub
//
//  Minimal helper for consistent Logger creation.
//

import OSLog

enum AppLogger {
    nonisolated static func category(_ category: String) -> Logger {
        Logger(subsystem: "com.llmhub", category: category)
    }
}
