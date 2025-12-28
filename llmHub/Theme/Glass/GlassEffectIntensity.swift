//
//  GlassEffectIntensity.swift
//  llmHub
//
//  Created by AI Assistant on 12/20/25.
//

import SwiftUI

/// Helper to map a 0-100% intensity scalar to native Liquid Glass parameters.
enum GlassEffectIntensity {

    /// Maps an intensity value (0.0 to 1.0) and tint color to a native GlassEffect.
    ///
    /// - Parameters:
    ///   - intensity: A value between 0.0 and 1.0.
    ///     - 0.0 returns `.identity` (fully clear, no blur/breakage).
    ///     - >0.0 returns `.regular` with scaled tint opacity.
    ///   - tint: The base tint color to apply (e.g. semantic tints).
    /// - Returns: A configured `GlassEffect`.
    static func native(intensity: Double, tint: Color = .clear) -> SwiftUI.Glass {
        if intensity <= 0.001 {
            return .identity
        }

        // Map 0-1 intensity to parameters
        // At 1.0, we use the full tint.
        // At 0.1, we use a very faint version of the tint.

        // Note: The native .glassEffect(.regular) already includes blur.
        // We control 'strength' primarily via the visibility of the tint
        // because the OS manages the blur radius dynamically based on context.
        // However, if we wanted to modulate blur strength, we would need
        // a custom material which isn't exposed in this convenient API.
        //
        // Thus, 'intensity' here primarily controls the "presence" of the glass
        // visual via the tint's opacity.

        return .regular.tint(tint.opacity(intensity))
    }
}

// MARK: - Double Extensions for Glass Intensity

extension Double {
    /// Converts a 0-100 intensity value to glass effect parameters.
    /// Returns a tuple containing the glass style and overlay opacity.
    var asGlassIntensity: (style: SwiftUI.Glass, overlay: Double) {
        // Normalize intensity from 0-100 to 0-1
        let normalizedIntensity = self / 100.0
        
        // Create glass style with intensity-based tint
        let style: SwiftUI.Glass
        if normalizedIntensity <= 0.001 {
            style = .identity
        } else {
            // Use a subtle tint that becomes more visible with higher intensity
            style = .regular.tint(Color.white.opacity(normalizedIntensity * 0.1))
        }
        
        // Calculate overlay opacity - higher intensity means less overlay
        let overlay = max(0.0, (1.0 - normalizedIntensity) * 0.3)
        
        return (style, overlay)
    }
}
