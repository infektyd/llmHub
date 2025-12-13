//
//  LiquidGlassAPI.swift
//  llmHub
//
//  Minimal compatibility layer for Apple's Liquid Glass API.
//
//  On macOS/iOS 26+, SwiftUI provides the `Glass` type and the `.glassEffect(...)` modifier.
//  This file keeps llmHub's call sites using `GlassEffect` and `GlassEffectContainer`.
//

import SwiftUI

public typealias GlassEffect = SwiftUI.Glass

/// Namespace container used for glass morphing (shim/no-op until we adopt a real morphing API).
@available(
    *, deprecated,
    message: "GlassEffectContainer is a no-op. Remove the wrapper and use your content directly."
)
public struct GlassEffectContainer<Content: View>: View {
    let namespace: Namespace.ID?
    let content: Content

    public init(namespace: Namespace.ID, @ViewBuilder content: () -> Content) {
        self.namespace = namespace
        self.content = content()
    }

    /// Initializer for spacing-based layout (used by GlassToolbar)
    public init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.namespace = nil
        self.content = content()
    }

    public var body: some View { content }
}

extension View {
    /// Identifies a view for glass morphing.
    ///
    /// On current OS builds this is a no-op; keep call sites stable.
    @available(*, deprecated, message: "glassEffectID is a no-op. Remove this call.")
    public func glassEffectID(_ id: String) -> some View { self }
}
