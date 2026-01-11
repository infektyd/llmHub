//
//  PreviewMode.swift
//  llmHub
//
//  Single-source detection for Xcode Canvas previews.
//

import Foundation

enum PreviewMode {
    static var isRunning: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        if env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" { return true }
        return false
    }
}
