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
