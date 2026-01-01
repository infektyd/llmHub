//
//  ArtifactCardView.swift
//  llmHub
//
//  Flat artifact card embedded in transcript
//  No glass effects - simple bordered card
//

import SwiftUI

/// Flat artifact card view for embedding in transcript
/// Flat artifact card view for embedding in transcript
struct ArtifactCardView: View {
    let payload: ArtifactPayload
    private var expandedBinding: Binding<Bool>?
    @State private var internalExpanded: Bool = true

    init(payload: ArtifactPayload) {
        self.payload = payload
        self.expandedBinding = nil
    }

    init(payload: ArtifactPayload, isExpanded: Binding<Bool>) {
        self.payload = payload
        self.expandedBinding = isExpanded
    }

    var body: some View {
        let isExpanded = expandedState.wrappedValue
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: iconForKind)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusTint)

                Text(payload.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    withAnimation {
                        expandedState.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Content (if expanded)
            if isExpanded {
                if payload.kind == .code {
                    codeContent
                } else {
                    textContent
                }
            }

            if payload.status == .failure {
                Text("Error")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            } else if payload.status == .pending {
                Text("Pending…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        }
        .frame(maxWidth: 700)
    }

    // MARK: - Private Views

    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(payload.previewText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.backgroundPrimary.opacity(0.5))
                }
        }
    }

    private var textContent: some View {
        Text(payload.previewText)
            .font(.system(size: 14))
            .foregroundStyle(AppColors.textPrimary)
            .textSelection(.enabled)
    }

    private var iconForKind: String {
        switch payload.kind {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .image: return "photo"
        case .toolResult: return "gearshape.2"
        case .other: return "doc"
        }
    }

    private var expandedState: Binding<Bool> {
        expandedBinding ?? $internalExpanded
    }

    private var statusTint: Color {
        switch payload.status {
        case .pending:
            return AppColors.textSecondary
        case .success:
            return AppColors.accent
        case .failure:
            return Color.red
        }
    }

    private var borderTint: Color {
        switch payload.status {
        case .pending:
            return AppColors.textPrimary.opacity(0.08)
        case .success:
            return AppColors.textPrimary.opacity(0.1)
        case .failure:
            return Color.red.opacity(0.35)
        }
    }
}

#if DEBUG
#Preview("ArtifactCard - Tool result") {
    ArtifactCardView(payload: Canvas2PreviewFixtures.toolResultArtifact())
        .padding()
        .frame(width: 900)
}

#Preview("ArtifactCard - File artifact (collapsed)") {
    @Previewable @State var expanded = false
    return ArtifactCardView(payload: Canvas2PreviewFixtures.codeFileArtifact(), isExpanded: $expanded)
        .padding()
        .frame(width: 900)
}

#Preview("ArtifactCard - Error") {
    @Previewable @State var expanded = true
    return ArtifactCardView(payload: Canvas2PreviewFixtures.errorArtifact(), isExpanded: $expanded)
        .padding()
        .frame(width: 900)
}

#Preview("ArtifactCard - Pending") {
    @Previewable @State var expanded = true
    let pending = ArtifactPayload(
        id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
        title: "Uploading…",
        kind: .other,
        status: .pending,
        previewText: "Waiting for tool output…",
        actions: [],
        metadata: nil
    )
    return ArtifactCardView(payload: pending, isExpanded: $expanded)
        .padding()
        .frame(width: 900)
}
#endif
