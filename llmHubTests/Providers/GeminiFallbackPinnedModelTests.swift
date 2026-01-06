import XCTest

@testable import llmHub

final class GeminiFallbackPinnedModelTests: XCTestCase {

    func testAFMFallbackUsesPinnedFlashModelID() {
        XCTAssertEqual(GeminiPinnedModels.afmFallbackFlash, "gemini-2.0-flash-001")

        // Guard against drifting to an unpinned alias.
        let pattern = try! NSRegularExpression(pattern: "^gemini-2\\.0-flash-\\d{3}$")
        let range = NSRange(location: 0, length: GeminiPinnedModels.afmFallbackFlash.utf16.count)
        XCTAssertNotNil(pattern.firstMatch(in: GeminiPinnedModels.afmFallbackFlash, range: range))
    }

    func testAFMFallbackTemperatureIsDeterministic() {
        XCTAssertEqual(GeminiPinnedModels.afmFallbackTemperature, 0.0)
    }
}
