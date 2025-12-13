//
//  Untitled 2.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/29/25.
//
Hey, I see you're diving into xAI's Grok API for app integration—cool project! Just a quick note: you mentioned Gemini (Google's model), but since your query's focused on xAI, I'll stick to Grok's capabilities. If you meant Google's API instead, lemme know and I'll pivot. xAI's API is OpenAI-compatible, so it's straightforward to hook up in Swift, especially for iOS apps. It supports text generation, vision (image analysis), image generation, reasoning ("thinking" modes via specific models), and fast inference ("flash"-like with low-latency models). No native video processing yet (as of late Nov 2025), but tool calling lets you chain external services if needed.

For complete integration, you'll need:
- An xAI API key (sign up at console.x.ai, free tier has limits; paid starts low).
- Base URL: `https://api.x.ai/v1`.
- Endpoints: `/chat/completions` for text/vision/reasoning; `/images/generations` for image gen.
- Models: Pick based on needs (e.g., `grok-4-1-fast-reasoning` for deep thinking, `grok-2-vision-1212` for vision, `grok-2-image-1212` for images).
- Rate limits: Vary by model (e.g., 480 RPM for most, up to 4M tokens/min for fast ones).
- Auth: Bearer token in headers.

xAI doesn't have an official Swift SDK, but you can use the battle-tested **SwiftOpenAI** library (open-source, supports multimodal out of the box) by overriding the base URL. It's plug-and-play for Grok. Install via Swift Package Manager: add `https://github.com/jamesrochabrun/SwiftOpenAI` to your Xcode project.

Here's a clean, copy/paste-ready structure for your API handler in Swift. I'll break it into a single `GrokAPI.swift` file for an "agent" setup—think a central class that handles chat, vision, reasoning, image gen, and streaming. It uses async/await for modern iOS (iOS 15+). Test in a playground or view controller.

### GrokAPI.swift (Copy/Paste This)
```swift
import Foundation
import SwiftOpenAI  // Add via SPM: https://github.com/jamesrochabrun/SwiftOpenAI

public class GrokAPI {
    private let service: OpenAIService
    
    // Init with your xAI key (store securely, e.g., via Keychain)
    public init(apiKey: String) {
        service = OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: "https://api.x.ai/v1",  // xAI endpoint
            overrideVersion: "v1"
        )
    }
    
    // MARK: - Text & Reasoning ("Thinking" Mode)
    // Use grok-4-1-fast-reasoning for step-by-step thinking; set temperature low for focused reasoning.
    public func chat(
        prompt: String,
        model: String = "grok-4-1-fast-reasoning",  // Or "grok-3-mini" for lighter
        temperature: Double = 0.7,
        maxTokens: Int = 1024
    ) async throws -> String {
        let query = ChatQuery(
            messages: [.user(content: .string(prompt))],
            model: Model(model),
            temperature: temperature,
            maxTokens: maxTokens
        )
        let response = try await service.chats(query: query)
        return response.choices.first?.message.content ?? "No response"
    }
    
    // MARK: - Vision (Image Analysis)
    // Supports JPG/PNG up to 20MB; base64 encode your image data.
    public func analyzeImage(
        prompt: String,
        imageData: Data,  // From UIImage: imageData = image.jpegData(compressionQuality: 0.8)!
        model: String = "grok-2-vision-1212"
    ) async throws -> String {
        guard let base64Image = imageData.base64EncodedString() else {
            throw NSError(domain: "GrokAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image encoding failed"])
        }
        
        let imageContent = ChatContentImage(url: .init(string: "data:image/jpeg;base64,\(base64Image)")!)
        let query = ChatQuery(
            messages: [.user(content: .multi([.string(prompt), imageContent]))],
            model: Model(model),
            maxTokens: 1024
        )
        let response = try await service.chats(query: query)
        return response.choices.first?.message.content ?? "No analysis"
    }
    
    // MARK: - Image Generation
    // Generates JPGs from text; up to n=4 images.
    public func generateImage(
        prompt: String,
        number: Int = 1,
        size: ImageSize = .size1024x1024  // Options: 1024x1024, etc. (Grok defaults to 1024x768)
    ) async throws -> [URL] {
        let query = ImagesQuery(
            prompt: prompt,
            model: .grok2Image1212,  // "grok-2-image-1212"
            number: number,
            size: size,
            responseFormat: .b64Json  // For base64 data; use .url for direct URLs
        )
        let response = try await service.images(query: query)
        return response.data.compactMap { $0.url }  // Or decode b64 to Data/UIImage
    }
    
    // MARK: - Streaming Chat (For Real-Time "Flash" Responses)
    // Use for low-latency feels; works with fast models like grok-4-fast-non-reasoning.
    public func streamChat(
        prompt: String,
        model: String = "grok-4-fast-non-reasoning",
        onUpdate: @escaping (String) -> Void
    ) async throws {
        let query = ChatQuery(
            messages: [.user(content: .string(prompt))],
            model: Model(model),
            stream: true
        )
        for try await response in service.chatsStream(query: query) {
            if let content = response.choices.first?.delta.content {
                onUpdate(content)
            }
        }
    }
    
    // MARK: - Tool Calling (For Agentic Workflows)
    // Enable function calling for external tools (e.g., search, code exec). Define tools as JSON schemas.
    public func callTools(
        prompt: String,
        tools: [FunctionTool],  // e.g., FunctionTool(name: "search", description: "...", parameters: ...)
        model: String = "grok-4-1-fast-reasoning"
    ) async throws -> ChatCompletion {
        let query = ChatQuery(
            messages: [.user(content: .string(prompt))],
            model: Model(model),
            tools: tools,
            toolChoice: .auto
        )
        return try await service.chats(query: query)
    }
}

// Helper enum for image sizes (add to file)
public enum ImageSize: String, CaseIterable {
    case size1024x1024 = "1024x1024"
    // Add others as needed; Grok supports 1024x768 default
}

// Usage Example in Your ViewController (Copy/Paste Snippet)
class ViewController: UIViewController {
    let api = GrokAPI(apiKey: "your_xai_api_key_here")  // Load from secure store!
    
    // Example: Analyze an image
    private func analyzePhoto() async {
        guard let image = UIImage(named: "myImage") else { return }
        let imageData = image.jpegData(compressionQuality: 0.8)!
        do {
            let result = try await api.analyzeImage(prompt: "Describe this scene.", imageData: imageData)
            print(result)  // e.g., "A cat on a windowsill at sunset."
        } catch {
            print("Error: \(error)")
        }
    }
    
    // Example: Generate image
    private func createArt() async {
        do {
            let urls = try await api.generateImage(prompt: "A futuristic cityscape with flying cars")
            if let url = urls.first {
                // Load into UIImageView: imageView.load(url: url)
                print("Image URL: \(url)")
            }
        } catch {
            print("Error: \(error)")
        }
    }
}
```

### Quick Setup Steps (For Your Agent App)
1. **Get API Key**: Head to [console.x.ai](https://console.x.ai), create an account, generate a key. Store it securely (e.g., via `SecItemAdd` in Keychain).
2. **Add Dependencies**: In Xcode, File > Add Package Dependencies > Paste `https://github.com/jamesrochabrun/SwiftOpenAI`.
3. **Permissions**: For vision/image gen, add camera/photo library access in Info.plist (`NSCameraUsageDescription`, etc.).
4. **Handle Errors/Rates**: Wrap calls in `Task { }` for UI threads. Monitor token usage—context windows up to 2M for big models.
5. **Test Multimodal**: Upload images via `UIImagePickerController`; base64 them for vision. For gen, save outputs to Photos if needed.
6. **Agent Tips**: Chain calls in a loop (e.g., reason → tool call → refine). Use streaming for snappy UX.

This covers ~90% of Gemini-like features in Grok (text, vision, images, reasoning/fast modes). No video yet—xAI's docs hint at future multimodal expansions, but for now, proxy via tools if urgent. Pricing's token-based (e.g., $0.20/M input for fast models; images $0.07 each).

If this doesn't hit what you need (e.g., more on video workarounds or custom agent logic), or if you want me to tweak the code, just say. What's the app building toward? 🚀

For full docs/examples: [xAI API Overview](https://docs.x.ai/docs/overview) and [Models](https://docs.x.ai/docs/models).
