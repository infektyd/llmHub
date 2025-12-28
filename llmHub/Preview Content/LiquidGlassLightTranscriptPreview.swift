//
//  LiquidGlassLightTranscriptPreview.swift
//  llmHub
//
//

#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

struct LiquidGlassLightTranscriptPreview: View {
    @State private var inputText = "Write a classic merge sort in Swift."

    // Mock Theme
    let theme = LiquidGlassLightTheme()

    var body: some View {
        ZStack {
            // Ambient Background
            Color(red: 0.96, green: 0.96, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Stub
                HStack {
                    Image(systemName: "sidebar.left")
                    Spacer()
                    Text("Liquid Glass")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                }
                .padding()
                .background(.ultraThinMaterial)

                // Transcript Surface
                GlassTranscriptSurface {
                    ScrollView {
                        VStack(spacing: 0) {
                            // User Message
                            NeonMessageRow(
                                message: .preview(
                                    role: "user",
                                    content: "Can you show me a merge sort implementation?"
                                ),
                                relatedToolCall: nil
                            )

                            // Assistant Message (Markdown)
                            NeonMessageRow(
                                message: .preview(
                                    role: "assistant",
                                    content: """
                                        Here is a generic `mergeSort` function in Swift:

                                        ```swift
                                        func mergeSort<T: Comparable>(_ array: [T]) -> [T] {
                                            guard array.count > 1 else { return array }
                                            let middle = array.count / 2
                                            let left = mergeSort(Array(array[..<middle]))
                                            let right = mergeSort(Array(array[middle...]))
                                            return merge(left, right)
                                        }
                                        ```

                                        It splits the array recursively.
                                        """
                                ),
                                relatedToolCall: nil
                            )

                            // Tool Call & Result
                            NeonMessageRow(
                                message: .preview(
                                    role: "assistant",
                                    content: "",
                                    toolCallsData: try? JSONEncoder().encode([
                                        ToolCall(
                                            id: "call_1", name: "swift_compiler", input: "{}")
                                    ])
                                ),
                                relatedToolCall: nil
                            )

                            NeonMessageRow(
                                message: .preview(
                                    role: "tool",
                                    content: "Build Succeeded (0.4s)\n\nstdout:\n- Compiling 42 files\n- Linking llmHub\n- Signing\n\nstderr:\n(none)\n\nNotes:\n- This is a long multi-line tool output\n- Collapsed preview must stay inside bubble",
                                    toolCallID: "call_1"
                                ),
                                relatedToolCall: ToolCall(
                                    id: "call_1", name: "swift_compiler", input: "{\"configuration\":\"Debug\",\"sdk\":\"macosx\"}")
                            )

                        }
                        .padding(LiquidGlassTokens.Spacing.transcriptPadding)
                    }
                } footer: {
                    // Composer Stub
                    HStack {
                        Image(systemName: "paperclip")
                        TextField("Message...", text: $inputText)
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
                .padding()
            }
        }
        .environment(\.theme, theme)
        .preferredColorScheme(.light)
    }
}

// Helper stub for preview
extension ChatMessageEntity {
    static func preview(
        role: String, content: String, toolCallID: String? = nil, toolCallsData: Data? = nil
    ) -> ChatMessageEntity {
        let domainRole = MessageRole(rawValue: role) ?? .user
        let domainMsg = ChatMessage(
            id: UUID(),
            role: domainRole,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: []
        )

        let msg = ChatMessageEntity(message: domainMsg)
        msg.toolCallID = toolCallID
        msg.toolCallsData = toolCallsData
        return msg
    }
}

#Preview {
    LiquidGlassLightTranscriptPreview()
}
