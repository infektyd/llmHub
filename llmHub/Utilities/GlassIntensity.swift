// Utilities/GlassIntensity.swift
import SwiftUI

extension Double {
    var asGlassIntensity: (style: GlassEffect, overlayOpacity: Double) {
        let n = self / 100.0
        switch n {
        case 0.0: return (.identity, 0.0)
        case 0.01...0.3: return (.clear, n * 0.4)
        case 0.31...0.7: return (.regular, n * 0.7)
        default: return (.regular, min(n * 0.9, 0.85))
        }
    }
}
