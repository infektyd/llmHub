//
//  EmailNotificationTool.swift
//  llmHub
//
//  Email and notification sending tool
//

import Foundation
import OSLog

/// Email Notification Tool conforming to the Tool protocol.
/// Sends emails and notifications.
/// Email Notification Tool conforming to the Tool protocol.
/// Sends emails and notifications.
struct EmailNotificationTool: Tool {
    let name = "email_notification"
    let description = """
        Send email notifications and alerts. \
        Supports HTML and plain text emails with attachments. \
        Use this tool when you need to send notifications, reports, or alerts via email.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "to": ToolProperty(
                    type: .string,
                    description: "Recipient email address"
                ),
                "subject": ToolProperty(
                    type: .string,
                    description: "Email subject line"
                ),
                "body": ToolProperty(
                    type: .string,
                    description: "Email body content"
                ),
                "body_type": ToolProperty(
                    type: .string,
                    description: "Email body format (default: plain)",
                    enumValues: ["plain", "html"]
                ),
                "cc": ToolProperty(
                    type: .string,
                    description: "Optional CC email addresses (comma-separated)"
                ),
                "bcc": ToolProperty(
                    type: .string,
                    description: "Optional BCC email addresses (comma-separated)"
                ),
            ],
            required: ["to", "subject", "body"]
        )
    }

    nonisolated var permissionLevel: ToolPermissionLevel { .sensitive }
    nonisolated var requiredCapabilities: [ToolCapability] { [.notifications] }
    nonisolated var weight: ToolWeight { .standard }
    nonisolated var isCacheable: Bool { false }

    private let logger = Logger(subsystem: "com.llmhub", category: "EmailNotificationTool")

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        throw ToolError.unavailable(
            reason:
                "Email service not configured. Set up SMTP server settings or email API credentials in Settings > Tools > Email."
        )
    }
}
