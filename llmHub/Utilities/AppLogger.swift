//
//  AppLogger.swift
//  llmHub
//
//  Minimal helper for consistent Logger creation.
//

import Foundation
import FoundationModels
import OSLog
import SwiftData

enum AppLogger {
    nonisolated static func category(_ category: String) -> Logger {
        Logger(subsystem: "com.llmhub", category: category)
    }

    @MainActor
    static func logAFMStatusOnLaunch() {
        let logger = AppLogger.category("AFM")

        if #available(macOS 15.0, iOS 18.0, *) {
            let availability = SystemLanguageModel.default.availability
            logger.info(
                "AFM: SystemLanguageModel.default.availability=\(String(describing: availability), privacy: .public)"
            )
            if availability != .available {
                logger.debug(
                    "AFM: Model assets not available. User may need to enable Apple Intelligence or download models."
                )
            }
        } else {
            logger.info("AFM: unsupported OS version")
        }
    }
}
