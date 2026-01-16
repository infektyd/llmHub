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

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AttachmentPreviewChip(attachment: attachment) {
                            onRemove(attachment.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            // Constrain height to prevent excessive growth, but enough for chips
            .frame(height: 38)
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
