//
//  PreviewSupport.swift
//  llmHub
//
//  Mock data and helpers for SwiftUI Previews
//

import Foundation
import SwiftUI

// MARK: - Preview Sample Data

struct PreviewData {
    // MARK: - Sample Text Content

    static let shortUserMessage = "How do I use SwiftUI?"
    static let longUserMessage =
        "I'm trying to build a chat interface in SwiftUI but I'm running into issues with the layout. The messages aren't scrolling properly and the input bar keeps getting hidden by the keyboard."

    static let shortAssistantMessage = "Here's a quick solution for you."
    static let longAssistantMessage = """
        That's a common challenge! Here are a few approaches:

        1. Use ScrollViewReader to scroll to the latest message
        2. Add .keyboardAdaptive() modifier to handle keyboard
        3. Consider using a GeometryReader for dynamic sizing

        Would you like me to show you some code examples?
        """

    static let sampleTimestamp = Date()
}

// MARK: - Previews

#Preview("Nordic Sample Data") {
    VStack(alignment: .leading, spacing: 20) {
        Text("Nordic Sample Data")
            .font(.headline)
            .padding(.bottom, 4)

        Group {
            DataRow(label: "Short User", text: PreviewData.shortUserMessage)
            DataRow(label: "Short Assistant", text: PreviewData.shortAssistantMessage)
            DataRow(label: "Long User", text: PreviewData.longUserMessage)
            DataRow(label: "Long Assistant", text: PreviewData.longAssistantMessage)
        }
    }
    .padding()
    .frame(width: 400)
}

private struct DataRow: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(text)
                .font(.body)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
        }
    }
}
