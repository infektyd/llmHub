//
//  SSEEventParser.swift
//  llmHub
//
//  Minimal SSE frame parser used by streaming providers.
//

import Foundation

/// Incremental parser for Server-Sent Events (SSE).
///
/// Rationale: URLSession `AsyncBytes.lines` can deliver partial/fragmented payloads when the server
/// emits multi-line `data:` fields or when JSON spans multiple TCP frames. This parser buffers
/// until a full SSE event frame boundary is observed before yielding `data:` payloads.
struct SSEEventParser: Sendable {
    private var buffer = Data()

    init() {}

    mutating func append(byte: UInt8) -> [String] {
        buffer.append(byte)
        return drainEvents()
    }

    mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        return drainEvents()
    }

    mutating func drainEvents() -> [String] {
        var payloads: [String] = []

        while let frameRange = nextFrameRange(in: buffer) {
            let frameData = buffer.subdata(in: frameRange.frame)
            buffer.removeSubrange(frameRange.consume)

            if let payload = parseDataPayload(fromFrame: frameData) {
                payloads.append(payload)
            }
        }

        return payloads
    }

    // MARK: - Framing

    private struct FrameRanges {
        let frame: Range<Data.Index>
        let consume: Range<Data.Index>
    }

    /// Returns the next complete SSE frame and the range to consume (including delimiter).
    private func nextFrameRange(in data: Data) -> FrameRanges? {
        // SSE frames are separated by a blank line (either "\n\n" or "\r\n\r\n").
        let lf = Data([0x0A, 0x0A])
        let crlf = Data([0x0D, 0x0A, 0x0D, 0x0A])

        let lfRange = data.range(of: lf)
        let crlfRange = data.range(of: crlf)

        let delimiterRange: Range<Data.Index>?
        if let a = lfRange, let b = crlfRange {
            delimiterRange = a.lowerBound <= b.lowerBound ? a : b
        } else {
            delimiterRange = lfRange ?? crlfRange
        }

        guard let delimiterRange else { return nil }

        return FrameRanges(
            frame: data.startIndex..<delimiterRange.lowerBound,
            consume: data.startIndex..<delimiterRange.upperBound
        )
    }

    // MARK: - Payload

    private func parseDataPayload(fromFrame frameData: Data) -> String? {
        guard !frameData.isEmpty else { return nil }
        guard let frameText = String(data: frameData, encoding: .utf8) else { return nil }

        var dataLines: [String] = []
        frameText.split(whereSeparator: \.isNewline).forEach { rawLine in
            let line = String(rawLine)
            guard line.hasPrefix("data:") else { return }
            // "data:" or "data: " are both valid; keep the remainder.
            let remainder = line.dropFirst(5)
            if remainder.first == " " {
                dataLines.append(String(remainder.dropFirst()))
            } else {
                dataLines.append(String(remainder))
            }
        }

        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.isEmpty ? nil : payload
    }
}

// MARK: - Event-aware SSE framing

/// An SSE frame containing both optional `event:` and required `data:` payload.
struct SSEEventFrame: Sendable, Equatable {
    var event: String?
    var data: String
}

/// SSE parser that preserves the `event:` field when present.
///
/// The returned `data` is the concatenation of all `data:` lines in a frame joined with `\n`.
struct SSEEventFrameParser: Sendable {
    private var buffer = Data()

    init() {}

    mutating func append(byte: UInt8) -> [SSEEventFrame] {
        buffer.append(byte)
        return drainFrames()
    }

    mutating func append(_ data: Data) -> [SSEEventFrame] {
        buffer.append(data)
        return drainFrames()
    }

    mutating func drainFrames() -> [SSEEventFrame] {
        var frames: [SSEEventFrame] = []

        while let frameRange = nextFrameRange(in: buffer) {
            let frameData = buffer.subdata(in: frameRange.frame)
            buffer.removeSubrange(frameRange.consume)

            if let frame = parseFrame(fromFrame: frameData) {
                frames.append(frame)
            }
        }

        return frames
    }

    // MARK: - Framing

    private struct FrameRanges {
        let frame: Range<Data.Index>
        let consume: Range<Data.Index>
    }

    private func nextFrameRange(in data: Data) -> FrameRanges? {
        // SSE frames are separated by a blank line (either "\n\n" or "\r\n\r\n").
        let lf = Data([0x0A, 0x0A])
        let crlf = Data([0x0D, 0x0A, 0x0D, 0x0A])

        let lfRange = data.range(of: lf)
        let crlfRange = data.range(of: crlf)

        let delimiterRange: Range<Data.Index>?
        if let a = lfRange, let b = crlfRange {
            delimiterRange = a.lowerBound <= b.lowerBound ? a : b
        } else {
            delimiterRange = lfRange ?? crlfRange
        }

        guard let delimiterRange else { return nil }

        return FrameRanges(
            frame: data.startIndex..<delimiterRange.lowerBound,
            consume: data.startIndex..<delimiterRange.upperBound
        )
    }

    // MARK: - Payload

    private func parseFrame(fromFrame frameData: Data) -> SSEEventFrame? {
        guard !frameData.isEmpty else { return nil }
        guard let frameText = String(data: frameData, encoding: .utf8) else { return nil }

        var eventName: String?
        var dataLines: [String] = []

        frameText.split(whereSeparator: \.isNewline).forEach { rawLine in
            let line = String(rawLine)

            if line.hasPrefix("event:") {
                let remainder = line.dropFirst(6)
                let normalized =
                    remainder.first == " " ? remainder.dropFirst() : remainder
                let trimmed = String(normalized).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { eventName = trimmed }
                return
            }

            guard line.hasPrefix("data:") else { return }
            let remainder = line.dropFirst(5)
            if remainder.first == " " {
                dataLines.append(String(remainder.dropFirst()))
            } else {
                dataLines.append(String(remainder))
            }
        }

        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }
        return SSEEventFrame(event: eventName, data: payload)
    }
}
