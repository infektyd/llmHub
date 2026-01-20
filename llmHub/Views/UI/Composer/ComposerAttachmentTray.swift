//
//  ComposerAttachmentTray.swift
//  llmHub
//
//  Created by Assistant.
//

import SwiftUI

struct ComposerAttachmentTray: View {
    let attachments: [Attachment]
    let onRemove: (UUID) -> Void

    private var uniqueAttachments: [Attachment] {
        var seen = Set<UUID>()
        return attachments.filter { attachment in
            seen.insert(attachment.id).inserted
        }
    }

    var body: some View {
        if !uniqueAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueAttachments) { attachment in
                        AttachmentPreviewChip(attachment: attachment) {
                            onRemove(attachment.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            // Constrain height to prevent excessive growth, but enough for tiles
            .frame(height: 64)
        }
    }
}

#if DEBUG
    #Preview {
        ComposerAttachmentTray(
            attachments: [
                Attachment(
                    filename: "script.py",
                    url: URL(fileURLWithPath: "/tmp/script.py"),
                    type: .code,
                    previewText: "print('hello')"
                ),
                Attachment(
                    filename: "image.png",
                    url: URL(fileURLWithPath: "/tmp/image.png"),
                    type: .image,
                    previewText: nil
                ),
            ],
            onRemove: { _ in }
        )
        .padding()
        .background(Color.gray.opacity(0.1))
    }
#endif
