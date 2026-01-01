//
//  TextualMessageView.swift
//  llmHub
//
//  Wrapper for Textual rendering.
//  Currently falls back to native Text() until Textual is fully integrated.
//

import SwiftUI

struct TextualMessageView: View {
    let content: String
    let isStreaming: Bool

    var body: some View {
        // TODO: Integrate Textual rendering
        // For now, simple markdown-capable text
        Text(LocalizedStringKey(content))
            .font(.system(size: 14))
            .foregroundStyle(AppColors.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    // Caching/Hashing stub
    private var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(content)
        return hasher.finalize()
    }
}
