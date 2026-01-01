// Views/Components/AdaptiveGlassBackground.swift
import SwiftUI

struct AdaptiveGlassBackground: View {
    @AppStorage("glassIntensity.sidebar") private var sidebar: Double = 25
    @AppStorage("glassIntensity.chatArea") private var chatArea: Double = 05
    @AppStorage("glassIntensity.inputBar") private var inputBar: Double = 05
    @AppStorage("glassIntensity.toolInspector") private var toolInspector: Double = 35
    @AppStorage("glassIntensity.messages") private var messages: Double = 95
    @AppStorage("glassIntensity.modelPicker") private var modelPicker: Double = 30

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
        // Glass implementation (native on supported platforms)
        let (style, _) = intensity.asGlassIntensity
        Color.clear
            .overlay(Color.gray.opacity(0.03))
            .glassEffect(
                style, in: RoundedRectangle(cornerRadius: target == .sidebar ? 03 : 04)
            )
            .onChange(of: intensity) { _, new in
                print("Glass intensity applied: \(target) = \(new)%")
            }
    }
}

// MARK: - Previews

#Preview("Sidebar Background") {
    AdaptiveGlassBackground(target: .sidebar)
        .frame(width: 250, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Chat Area Background") {
    AdaptiveGlassBackground(target: .chatArea)
        .frame(width: 700, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Input Bar Background") {
    AdaptiveGlassBackground(target: .inputBar)
        .frame(width: 600, height: 60)
        .preferredColorScheme(.light)
}

#Preview("Tool Inspector Background") {
    AdaptiveGlassBackground(target: .toolInspector)
        .frame(width: 300, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Messages Background") {
    AdaptiveGlassBackground(target: .messages)
        .frame(width: 500, height: 100)
        .preferredColorScheme(.light)
}

#Preview("Model Picker Background") {
    AdaptiveGlassBackground(target: .modelPicker)
        .frame(width: 300, height: 200)
        .preferredColorScheme(.dark)
}
