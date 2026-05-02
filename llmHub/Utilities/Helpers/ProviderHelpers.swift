//
//  ProviderHelpers.swift
//  llmHub
//
//  Shared utilities for provider UI operations.
//

import CryptoKit
import Foundation

/// Creates a stable UUID from a string identifier.
/// The same input string always produces the same UUID.
/// - Parameter string: The input string (e.g., provider ID or model ID)
/// - Returns: A deterministic UUID based on the input string
func stableUUID(for string: String) -> UUID {
    let md5Data = Insecure.MD5.hash(data: string.data(using: .utf8) ?? Data())
    let bytes = Array(md5Data)

    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

/// Returns the display name for a provider ID.
/// - Parameter providerID: The provider identifier (e.g., "openai", "anthropic")
/// - Returns: The human-readable display name
func providerDisplayName(for providerID: String) -> String {
    switch providerID.lowercased() {
    case "openai": return "OpenAI"
    case "anthropic": return "Anthropic"
    case "google": return "Google AI"
    case "mistral": return "Mistral AI"
    case "xai": return "xAI"
    case "openrouter": return "OpenRouter"
    default: return providerID.capitalized
    }
}

/// Returns the SF Symbol icon name for a provider ID.
/// - Parameter providerID: The provider identifier
/// - Returns: The SF Symbol icon name
func providerIcon(for providerID: String) -> String {
    switch providerID.lowercased() {
    case "openai": return "sparkles"
    case "anthropic": return "brain.head.profile"
    case "google": return "cloud.fill"
    case "mistral": return "wind"
    case "xai": return "bolt.circle.fill"
    case "openrouter": return "arrow.triangle.branch"
    default: return "cpu"
    }
}
