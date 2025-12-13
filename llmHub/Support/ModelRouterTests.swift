import Foundation

/// Unit tests for ModelRouter endpoint routing logic
/// Run these in Xcode's test navigator or via command line
struct ModelRouterTests {

    static func runAllTests() {
        print("Running ModelRouter Tests...")

        testGPT5Family()
        testO1Family()
        testStandardModels()

        print("✅ All tests passed!")
    }

    // MARK: - Test Cases

    static func testGPT5Family() {
        assert(
            ModelRouter.endpoint(for: "gpt-5") == .responses, "gpt-5 should use responses endpoint")
        assert(
            ModelRouter.endpoint(for: "gpt-5-turbo") == .responses,
            "gpt-5-turbo should use responses endpoint")
        assert(
            ModelRouter.endpoint(for: "gpt-5-preview") == .responses,
            "gpt-5-preview should use responses endpoint")
        print("✅ GPT-5 family tests passed")
    }

    static func testO1Family() {
        assert(ModelRouter.endpoint(for: "o1") == .responses, "o1 should use responses endpoint")
        assert(
            ModelRouter.endpoint(for: "o1-preview") == .responses,
            "o1-preview should use responses endpoint")
        assert(
            ModelRouter.endpoint(for: "o1-mini") == .responses,
            "o1-mini should use responses endpoint")
        print("✅ O1 family tests passed")
    }

    static func testStandardModels() {
        assert(
            ModelRouter.endpoint(for: "gpt-4") == .chatCompletions,
            "gpt-4 should use chat completions")
        assert(
            ModelRouter.endpoint(for: "gpt-4-turbo") == .chatCompletions,
            "gpt-4-turbo should use chat completions")
        assert(
            ModelRouter.endpoint(for: "gpt-3.5-turbo") == .chatCompletions,
            "gpt-3.5-turbo should use chat completions")
        assert(
            ModelRouter.endpoint(for: "gpt-4o") == .chatCompletions,
            "gpt-4o should use chat completions")
        print("✅ Standard models tests passed")
    }
}

// Uncomment to run tests
// ModelRouterTests.runAllTests()
