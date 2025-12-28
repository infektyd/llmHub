//
//  AFMDiagnosticsState.swift
//  llmHub
//
//

import Foundation
import FoundationModels
import Observation
import SwiftUI

@Observable
final class AFMDiagnosticsState {
    var isAvailable: Bool = false
    var availability: SystemLanguageModel.Availability?
    var reasonText: String = "Not checked"
    var lastCheckTime: Date?
    var checkCount: Int = 0

    var statusColor: Color {
        isAvailable ? Color.green : Color.red
    }

    var timeSinceCheck: String {
        guard let lastCheck = lastCheckTime else { return "Never" }
        let elapsed = Date().timeIntervalSince(lastCheck)
        if elapsed < 1 { return "Just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        return "\(Int(elapsed / 60))m ago"
    }
}
