// Views/Components/AdaptiveGlassBackground.swift
import SwiftUI

struct AdaptiveGlassBackground: View {
    @Environment(\.theme) private var theme

    @AppStorage("glassIntensity.sidebar") private var sidebar: Double = 50
    @AppStorage("glassIntensity.chatArea") private var chatArea: Double = 10
    @AppStorage("glassIntensity.inputBar") private var inputBar: Double = 10
    @AppStorage("glassIntensity.toolInspector") private var toolInspector: Double = 65
    @AppStorage("glassIntensity.messages") private var messages: Double = 95
    @AppStorage("glassIntensity.modelPicker") private var modelPicker: Double = 50

    let target: Target

    enum Target { case sidebar, chatArea, inputBar, toolInspector, messages, modelPicker }

    private var intensity: Double {
        switch target {
        case .sidebar: return sidebar
        case .chatArea: return chatArea
        case .inputBar: return inputBar
        case .toolInspector: return toolInspector
        case .messages: return messages
        case .modelPicker: return modelPicker
        }
    }

    var body: some View {
        if theme.usesGlassEffect {
            // Glass implementation
            let (style, overlay) = intensity.asGlassIntensity
            Color.clear
                .overlay(Color.black.opacity(overlay))
                .glassEffect(
                    style, in: RoundedRectangle(cornerRadius: target == .sidebar ? 06 : 08)
                )
                .onChange(of: intensity) { _, new in
                    print("Glass intensity applied: \(target) = \(new)%")
                }
        } else {
            // Flat fallback
            RoundedRectangle(cornerRadius: target == .sidebar ? 6 : theme.cornerRadius)
                .fill(theme.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: target == .sidebar ? 6 : theme.cornerRadius)
                        .stroke(theme.textTertiary.opacity(0.15), lineWidth: theme.borderWidth)
                )
        }
    }
}
