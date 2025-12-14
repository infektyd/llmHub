//
//  ImageGenerationTool.swift
//  llmHub
//
//  AI image generation tool
//

import Foundation
import OSLog

/// Image Generation Tool conforming to the Tool protocol.
/// Generates images using AI models (DALL-E, Stable Diffusion, etc.).
/// Image Generation Tool conforming to the Tool protocol.
/// Generates images using AI models (DALL-E, Stable Diffusion, etc.).
struct ImageGenerationTool: Tool {
    let name = "image_generation"
    let description = """
        Generate images from text descriptions using AI models. \
        Supports various image generation APIs including DALL-E and Stable Diffusion. \
        Use this tool when you need to create images, artwork, or visual concepts.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "prompt": ToolProperty(
                    type: .string,
                    description: "Text description of the image to generate"
                ),
                "model": ToolProperty(
                    type: .string,
                    description: "Image generation model to use (default: dall-e-3)",
                    enumValues: ["dall-e-3", "dall-e-2", "stable-diffusion"]
                ),
                "size": ToolProperty(
                    type: .string,
                    description: "Image dimensions (default: 1024x1024)",
                    enumValues: ["1024x1024", "1792x1024", "1024x1792"]
                ),
                "quality": ToolProperty(
                    type: .string,
                    description: "Image quality (default: standard)",
                    enumValues: ["standard", "hd"]
                ),
                "style": ToolProperty(
                    type: .string,
                    description: "Image style (default: vivid)",
                    enumValues: ["vivid", "natural"]
                ),
            ],
            required: ["prompt"]
        )
    }

    nonisolated var permissionLevel: ToolPermissionLevel { .standard }
    nonisolated var requiredCapabilities: [ToolCapability] { [.imageGeneration] }
    nonisolated var weight: ToolWeight { .heavy }
    nonisolated var isCacheable: Bool { true }

    private let logger = Logger(subsystem: "com.llmhub", category: "ImageGenerationTool")

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        throw ToolError.unavailable(
            reason:
                "Image generation not configured. Add API keys for DALL-E or Stable Diffusion in Settings > Tools > Image Generation."
        )
    }
}
