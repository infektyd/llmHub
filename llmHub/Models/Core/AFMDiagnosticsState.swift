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
    var foundationModelsDiagnosticsEnabled: Bool {
        get { FoundationModelsDiagnostics.isEnabled }
        set { FoundationModelsDiagnostics.isEnabled = newValue }
    }

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

    func runProbe() {
        FoundationModelsDiagnostics.probe()

        // Update local state for UI
        checkCount += 1
        lastCheckTime = Date()

        if #available(macOS 15.0, iOS 18.0, *) {
            let availability = SystemLanguageModel.default.availability
            self.availability = availability
            self.isAvailable = availability == .available

            switch availability {
            case .available:
                reasonText = "Available"
            case .unavailable(let reason):
                reasonText = "Unavailable: \(String(describing: reason))"
            @unknown default:
                reasonText = "Unknown"
            }
        }
    }

    func runSmallGenerate() {
        Task {
            if #available(macOS 15.0, iOS 18.0, *) {
                let availability = SystemLanguageModel.default.availability
                guard availability == .available else {
                    if case .unavailable(let reason) = availability {
                        FoundationModelsDiagnostics.logStreamEvent(
                            "skip",
                            reason: "small_generate_unavailable:\(String(describing: reason))"
                        )
                    }
                    return
                }
            }

            FoundationModelsDiagnostics.logRequestStart(useCase: "small_generate_test")
            let start = CFAbsoluteTimeGetCurrent()

            do {
                if #available(macOS 15.0, iOS 18.0, *) {
                    let model = SystemLanguageModel(useCase: .contentTagging)
                    let session = LanguageModelSession(model: model)
                    let prompt = "Say hello in one sentence."

                    let response = try await session.respond(to: prompt)
                    let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    FoundationModelsDiagnostics.logRequestSuccess(latencyMs: latency)
                    print("Test generate success: \(response.content)")
                }
            } catch {
                let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
                FoundationModelsDiagnostics.logRequestFail(latencyMs: latency, error: error)
            }
        }
    }
}
