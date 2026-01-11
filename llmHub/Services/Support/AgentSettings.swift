//
//  AgentSettings.swift
//  llmHub
//

import Foundation

enum AgentSettings {
    static let maxIterationsKey = "agent.maxIterations"

    static let defaultMaxIterations: Int = 10
    static let minMaxIterations: Int = 1
    static let maxMaxIterations: Int = 200

    static func clampMaxIterations(_ value: Int) -> Int {
        min(max(value, minMaxIterations), maxMaxIterations)
    }

    static func maxIterations(defaults: UserDefaults = .standard) -> Int {
        let raw = defaults.integer(forKey: maxIterationsKey)
        // `integer(forKey:)` returns 0 when missing.
        let value = (raw == 0) ? defaultMaxIterations : raw
        return clampMaxIterations(value)
    }

    static func setMaxIterations(_ value: Int, defaults: UserDefaults = .standard) {
        defaults.set(clampMaxIterations(value), forKey: maxIterationsKey)
    }
}
