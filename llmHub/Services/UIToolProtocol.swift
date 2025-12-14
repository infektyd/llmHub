// Services/UIToolProtocol.swift
// Protocol for tools that require MainActor isolation for UI integration

import Foundation

/// Protocol for tools that need MainActor isolation for UI callbacks.
/// Tools that conform to this protocol can have UI-related properties and methods.
@MainActor
protocol UITool: Tool {
    /// Callback for user approval (optional)
    var approvalHandler: ((String, Any) async -> Bool)? { get set }
    
    /// Callback for execution start (optional)
    var onExecutionStart: ((Any) -> Void)? { get set }
    
    /// Callback for execution completion (optional)
    var onExecutionComplete: ((Any) -> Void)? { get set }
}