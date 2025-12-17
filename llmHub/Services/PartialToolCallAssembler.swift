//
//  PartialToolCallAssembler.swift
//  llmHub
//
//  Centralized assembly for streaming tool/function call deltas.
//

import Foundation

/// Incrementally assembles streamed tool call deltas and only finalizes calls once the JSON input is valid.
nonisolated struct PartialToolCallAssembler: Sendable {
    struct Partial: Sendable {
        var index: Int
        var id: String?
        var name: String?
        var arguments: String
    }

    private var byIndex: [Int: Partial] = [:]
    private var emittedIDs: Set<String> = []
    private var emittedIndices: Set<Int> = []

    init() {}

    mutating func ingest(index: Int, id: String?, name: String?, argumentsDelta: String?) {
        var partial = byIndex[index] ?? Partial(index: index, id: nil, name: nil, arguments: "")
        if let id, !id.isEmpty { partial.id = id }
        if let name, !name.isEmpty { partial.name = name }
        if let argumentsDelta, !argumentsDelta.isEmpty { partial.arguments += argumentsDelta }
        byIndex[index] = partial
    }

    /// Finalizes a specific call when the provider indicates tool-call completion.
    mutating func finalize(index: Int) -> ToolCall? {
        guard let partial = byIndex[index] else { return nil }
        guard let name = partial.name, !name.isEmpty else { return nil }
        let id = (partial.id?.isEmpty == false) ? partial.id! : "call_\(index)"

        if emittedIndices.contains(index) || emittedIDs.contains(id) { return nil }
        guard Self.isValidJSONObjectString(partial.arguments) else { return nil }

        emittedIndices.insert(index)
        emittedIDs.insert(id)
        return ToolCall(id: id, name: name, input: partial.arguments)
    }

    /// Finalizes all calls that are currently valid.
    mutating func finalizeAll() -> [ToolCall] {
        byIndex.keys.sorted().compactMap { finalize(index: $0) }
    }

    /// Returns all assembled calls (including non-finalizable), best-effort.
    func snapshotSorted() -> [ToolCall] {
        byIndex.values.sorted(by: { $0.index < $1.index }).compactMap { partial in
            guard let name = partial.name, !name.isEmpty else { return nil }
            let id = (partial.id?.isEmpty == false) ? partial.id! : "call_\(partial.index)"
            return ToolCall(id: id, name: name, input: partial.arguments)
        }
    }

    private static func isValidJSONObjectString(_ s: String) -> Bool {
        guard let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
