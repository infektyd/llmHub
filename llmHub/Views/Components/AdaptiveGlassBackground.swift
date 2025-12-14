// Views/Components/AdaptiveGlassBackground.swift
import SwiftUI

struct AdaptiveGlassBackground: View {
    @AppStorage("glassIntensity.sidebar") private var sidebar: Double = 95
    @AppStorage("glassIntensity.chatArea") private var chatArea: Double = 10
    @AppStorage("glassIntensity.inputBar") private var inputBar: Double = 10
    @AppStorage("glassIntensity.toolInspector") private var toolInspector: Double = 65
    @AppStorage("glassIntensity.messages") private var messages: Double = 95
    @AppStorage("glassIntensity.modelPicker") private var modelPicker: Double = 100

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
        let (style, overlay) = intensity.asGlassIntensity
        Color.clear
            .overlay(Color.black.opacity(overlay))
            .glassEffect(style, in: RoundedRectangle(cornerRadius: target == .sidebar ? 12 : 16))
            .onChange(of: intensity) { _, new in
                print("Glass intensity applied: \(target) = \(new)%")
            }
    }
}
