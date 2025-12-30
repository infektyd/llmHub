//
//  NeonDarkTranscriptPreview.swift
//  llmHub
//
//  Created by AI Assistant on 2025-12-13.
//

import SwiftUI

struct NeonDarkTranscriptPreview: View {
    @State private var theme = CanvasPreviewTheme.screenshotDark

    var body: some View {
        CanvasWorkbenchShell(theme: $theme)
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }
}

#Preview {
    NeonDarkTranscriptPreview()
}
