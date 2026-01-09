//
//  ThinkTagStreamExtractor.swift
//  llmHub
//

import Foundation

/// Incrementally extracts `<think>...</think>` segments from streamed text.
///
/// Output inside `<think>` is emitted as thinking, and removed from visible assistant text.
struct ThinkTagStreamExtractor: Sendable {
    private var buffer: String = ""
    private var inThink: Bool = false

    init() {}

    mutating func process(delta: String) -> (visible: String, thinking: String) {
        guard !delta.isEmpty else { return ("", "") }
        buffer += delta

        var visibleOut = ""
        var thinkingOut = ""

        while true {
            if inThink {
                if let endRange = buffer.range(of: "</think>") {
                    thinkingOut += String(buffer[..<endRange.lowerBound])
                    buffer = String(buffer[endRange.upperBound...])
                    inThink = false
                    continue
                }

                // Emit safely while keeping a tail for a potential closing tag split.
                let tail = 16
                guard buffer.count > tail else { break }
                let emitCount = buffer.count - tail
                thinkingOut += String(buffer.prefix(emitCount))
                buffer = String(buffer.suffix(tail))
                break
            } else {
                if let startRange = buffer.range(of: "<think>") {
                    visibleOut += String(buffer[..<startRange.lowerBound])
                    buffer = String(buffer[startRange.upperBound...])
                    inThink = true
                    continue
                }

                // Emit safely while keeping a tail for a potential opening tag split.
                let tail = 8
                guard buffer.count > tail else { break }
                let emitCount = buffer.count - tail
                visibleOut += String(buffer.prefix(emitCount))
                buffer = String(buffer.suffix(tail))
                break
            }
        }

        return (visibleOut, thinkingOut)
    }

    mutating func flush() -> (visible: String, thinking: String) {
        defer { buffer = "" }
        if inThink {
            inThink = false
            return ("", buffer)
        }
        return (buffer, "")
    }
}
