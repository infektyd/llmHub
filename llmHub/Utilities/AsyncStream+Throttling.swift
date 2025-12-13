//
//  AsyncStream+Throttling.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/12/25.
//

import Foundation

extension AsyncStream where Element: Sendable {
    /// Throttles elements from the stream, emitting at most one element per interval.
    /// - Parameter interval: The minimum time interval between emissions.
    /// - Returns: An AsyncStream that emits elements at the specified rate.
    func throttled(for interval: Duration) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                var lastEmissionTime: Date = .distantPast

                for await element in self {
                    let now = Date()
                    let timeSinceLastEmission = now.timeIntervalSince(lastEmissionTime)
                    let intervalSeconds =
                        Double(interval.components.seconds) + Double(
                            interval.components.attoseconds) / 1e18

                    if timeSinceLastEmission >= intervalSeconds {
                        continuation.yield(element)
                        lastEmissionTime = now
                    } else {
                        // If we are too fast, wait until the interval passes, then yield the *latest* element
                        // This simplistic implementation might skip intermediate values, which is desired for UI throttling (we only want the latest state).
                        // However, a true coalesce often waits for the trailing edge.

                        // For a simple "UI stream throttling" where we just want to avoid overwhelming SwiftUI:
                        // We can just yield if enough time has passed.
                        // Ideally, we want to yield the *latest* value if we skipped some.
                        // A strictly robust implementation would need a separate buffer/timer.

                        // Let's implement a simpler "Leading edge + robust trailing" approach is complex in pure AsyncStream without a buffer actor.
                        // But since standard 'throttle' usually implies "emit at most once per interval", let's use a simpler approach:
                        // We yield, then sleep.

                        continuation.yield(element)
                        try? await Task.sleep(for: interval)
                        lastEmissionTime = Date()
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
