#!/usr/bin/env swift
import Foundation

struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let displayName: String?
        let supportedGenerationMethods: [String]?
        let inputTokenLimit: Int?
        let outputTokenLimit: Int?
    }

    let models: [Model]
}

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !apiKey.isEmpty else {
    fail("Missing GOOGLE_API_KEY. Example: GOOGLE_API_KEY=... scripts/verify_gemini_models.swift")
}

let preferredPinned = "models/gemini-2.0-flash-001"

let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
let (data, response) = try await URLSession.shared.data(from: url)

guard let http = response as? HTTPURLResponse else {
    fail("Non-HTTP response")
}

guard (200...299).contains(http.statusCode) else {
    let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
    fail("HTTP \(http.statusCode) from Models endpoint:\n\(body)")
}

let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)

let byName = Dictionary(uniqueKeysWithValues: decoded.models.map { ($0.name, $0) })

if let model = byName[preferredPinned] {
    print("✅ Found pinned model: \(model.name) (\(model.displayName ?? "(no displayName)"))")

    let methods = Set(model.supportedGenerationMethods ?? [])
    print("   supportedGenerationMethods: \(methods.sorted().joined(separator: ", "))")
    if methods.contains("generateContent") {
        print("   ✅ supports: generateContent")
    } else {
        print("   ❌ missing: generateContent")
    }
    if methods.contains("streamGenerateContent") {
        print("   ✅ supports: streamGenerateContent")
    } else {
        print("   ⚠️  streamGenerateContent not listed (may still work depending on API)")
    }

    print("   inputTokenLimit: \(model.inputTokenLimit.map(String.init) ?? "nil")")
    print("   outputTokenLimit: \(model.outputTokenLimit.map(String.init) ?? "nil")")

    print("\nModel ID to pin in llmHub (without 'models/' prefix): gemini-2.0-flash-001")
    exit(0)
}

print("❌ Did not find expected pinned model: \(preferredPinned)")

let flash20 = decoded.models
    .map { $0.name }
    .filter { $0.hasPrefix("models/gemini-2.0-flash") }
    .sorted()

if !flash20.isEmpty {
    print("\nFound Gemini 2.0 Flash candidates:")
    for name in flash20 {
        print(" - \(name)")
    }
}

let flashAny = decoded.models
    .map { $0.name }
    .filter { $0.contains("flash") && $0.contains("gemini") }
    .sorted()

if !flashAny.isEmpty {
    print("\nOther Gemini Flash-like candidates:")
    for name in flashAny.prefix(30) {
        print(" - \(name)")
    }
    if flashAny.count > 30 {
        print(" - … (\(flashAny.count - 30) more)")
    }
}

fail("Pinned model not found. If Google deprecated it, pick the closest pinned successor and update GeminiPinnedModels.afmFallbackFlash.")
