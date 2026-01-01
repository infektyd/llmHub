//
//  PreviewMode.swift
//  llmHub
//
//  Single-source detection for Xcode Canvas previews.
//

import Foundation

enum PreviewMode {
    static var isRunning: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

