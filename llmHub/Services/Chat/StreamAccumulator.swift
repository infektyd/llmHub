//
//  StreamAccumulator.swift
//  llmHub
//
//  Lightweight state machine for streaming tokens.
//

import Foundation
import OSLog

/// Manages streaming token buffers with a small state machine.
actor StreamAccumulator {
    enum State: Equatable {
        case idle
        case active(token: String, buffer: String)
        case completed(token: String, final: String)
        case failed(token: String, error: String)
    }

    private var state: State = .idle
    private let logger = AppLogger.category("StreamAccumulator")

    /// Begin tracking a new stream.
    func begin(token: String) {
        state = .active(token: token, buffer: "")
    }

    /// Append a token delta to the active buffer.
    /// - Parameters:
    ///   - token: Stream identifier.
    ///   - delta: Incoming text delta.
    /// - Returns: Updated buffer when appended, otherwise nil.
    func append(token: String, delta: String) -> String? {
        switch state {
        case .idle:
            logger.debug("append called before begin for token \(token, privacy: .public)")
            return nil
        case .active(let current, var buffer) where current == token:
            buffer.append(delta)
            state = .active(token: current, buffer: buffer)
            return buffer
        case .active(let current, _):
            logger.debug("Ignoring token update for mismatched stream \(token, privacy: .public) (current: \(current, privacy: .public))")
            return nil
        case .completed(let current, let final) where current == token:
            logger.debug("Late delta after completion for token \(token, privacy: .public)")
            return final
        case .failed(let current, _) where current == token:
            logger.debug("Ignoring delta after failure for token \(token, privacy: .public)")
            return nil
        default:
            logger.debug("Ignoring token update for inactive stream \(token, privacy: .public)")
            return nil
        }
    }

    /// Mark the stream as complete.
    /// - Parameters:
    ///   - token: Stream identifier.
    ///   - final: Final text to persist.
    /// - Returns: Final buffer when accepted, otherwise nil.
    func complete(token: String, final: String) -> String? {
        switch state {
        case .active(let current, let buffer) where current == token:
            let finalValue = final.isEmpty ? buffer : final
            state = .completed(token: current, final: finalValue)
            return finalValue
        case .completed(let current, let finalBuffer) where current == token:
            logger.debug("Completion already recorded for token \(token, privacy: .public)")
            return finalBuffer
        case .failed(let current, _) where current == token:
            logger.debug("Ignoring completion after failure for token \(token, privacy: .public)")
            return nil
        default:
            logger.debug("Ignoring completion for inactive stream \(token, privacy: .public)")
            return nil
        }
    }

    /// Record a stream failure.
    func fail(token: String, error: Error) {
        let message = error.localizedDescription
        switch state {
        case .active(let current, _), .completed(let current, _), .failed(let current, _):
            if current == token {
                logger.error("Stream failed for token \(token, privacy: .public): \(message, privacy: .public)")
                state = .failed(token: token, error: message)
            } else {
                logger.debug("Ignoring failure for inactive stream \(token, privacy: .public)")
            }
        case .idle:
            logger.debug("Ignoring failure for inactive stream \(token, privacy: .public)")
        }
    }

    /// Reset the accumulator to idle.
    func reset() {
        state = .idle
    }

    /// Current state for debugging.
    func currentState() -> State {
        state
    }
}
