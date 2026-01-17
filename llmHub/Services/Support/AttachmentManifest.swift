//
//  AttachmentManifest.swift
//  llmHub
//
//  Builds attachment manifest as a dedicated ChatMessage for staged attachments.
//

import Foundation

/// Builds attachment manifest messages for model context.
enum AttachmentManifest {

    /// Maximum number of attachments to include in manifest.
    private static let maxAttachments = 10

    /// Create a manifest message for staged attachments.
    /// - Parameter stagedAttachments: The attachments on the outgoing user message.
    /// - Returns: A ChatMessage with manifest content, or nil if no attachments.
    static func makeManifestMessage(stagedAttachments: [SandboxedArtifact]) -> ChatMessage? {
        guard !stagedAttachments.isEmpty else { return nil }

        let limited = Array(stagedAttachments.prefix(maxAttachments))
        var xml = "<attachments count=\"\(limited.count)\">\n"

        for artifact in limited {
            xml += "  <file id=\"\(artifact.id.uuidString)\" "
            xml += "name=\"\(escapeXML(artifact.filename))\" "
            xml += "type=\"\(artifact.mimeType)\" "
            xml += "bytes=\"\(artifact.sizeBytes)\"/>\n"
        }

        xml +=
            "  Use artifact_read_text(id) for text files or artifact_describe_image(id) for images.\n"
        xml += "</attachments>"

        return ChatMessage(
            id: UUID(),
            role: .system,
            content: xml,
            parts: [.text(xml)],
            createdAt: Date(),
            codeBlocks: []
        )
    }

    /// Calculate manifest size for logging.
    static func manifestSize(for attachments: [SandboxedArtifact]) -> (chars: Int, bytes: Int) {
        guard let msg = makeManifestMessage(stagedAttachments: attachments) else {
            return (0, 0)
        }
        let chars = msg.content.count
        let totalBytes = attachments.reduce(0) { $0 + $1.sizeBytes }
        return (chars, totalBytes)
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
