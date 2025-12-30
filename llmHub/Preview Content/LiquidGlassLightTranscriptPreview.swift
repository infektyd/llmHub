//
//  LiquidGlassLightTranscriptPreview.swift
//  llmHub
//
//

import SwiftUI

struct LiquidGlassLightTranscriptPreview: View {
    @State private var theme = CanvasPreviewTheme.screenshotLight

    var body: some View {
        CanvasWorkbenchShell(theme: $theme)
            .previewEnvironment()
            .preferredColorScheme(.light)
    }
}

#Preview {
    LiquidGlassLightTranscriptPreview()
}
