//
//  ProviderHelpers.swift
//  llmHub
//
//  Shared utilities for provider UI operations.
//

import Foundation

/// Creates a stable UUID from a string identifier.
/// The same input string always produces the same UUID.
/// - Parameter string: The input string (e.g., provider ID or model ID)
/// - Returns: A deterministic UUID based on the input string
func stableUUID(for string: String) -> UUID {
    // Create deterministic UUID from string hash
    let data = string.data(using: .utf8)!
    let hash = data.withUnsafeBytes { bytes in
        var hasher = Hasher()
        hasher.combine(bytes: UnsafeRawBufferPointer(start: bytes.baseAddress, count: bytes.count))
        return hasher.finalize()
    }
    
    // Convert hash to UUID bytes (pad/truncate to 16 bytes)
    var uuidBytes: [UInt8] = Array(repeating: 0, count: 16)
    withUnsafeBytes(of: hash.bigEndian) { hashBytes in
        let copyCount = min(hashBytes.count, 16)
        for i in 0..<copyCount {
            uuidBytes[i] = hashBytes[i]
        }
    }
    
    return UUID(uuid: (
        uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
        uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
        uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
        uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
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




















