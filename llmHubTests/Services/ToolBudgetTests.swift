//
//  ToolBudgetTests.swift
//  llmHubTests
//
//  Verification tests for tool budget mechanism
//

import Foundation
import XCTest

@testable import llmHub

class ToolBudgetTests: XCTestCase {

    func testToolBudgetResolve_Zen() {
        let budget = ToolBudget.resolve(for: .zen)
        XCTAssertEqual(budget.maxTools, 12, "Zen policy should have 12 tool budget")
    }

    func testToolBudgetResolve_Workhorse() {
        let budget = ToolBudget.resolve(for: .workhorse)
        XCTAssertEqual(budget.maxTools, Int.max, "Workhorse policy should have unlimited tools")
    }

    func testToolBudgetEnforcer_Underbudget() {
        let tools = createMockTools(count: 5)
        let budget = ToolBudget(maxTools: 10)

        let result = ToolBudgetEnforcer.applyBudget(to: tools, budget: budget)

        XCTAssertEqual(result.count, 5, "Should return all tools when under budget")
    }

    func testToolBudgetEnforcer_Overbudget() {
        let tools = createMockTools(count: 15)
        let budget = ToolBudget(maxTools: 8)

        let result = ToolBudgetEnforcer.applyBudget(to: tools, budget: budget)

        XCTAssertEqual(result.count, 8, "Should cap at budget limit")
    }

    func testToolBudgetEnforcer_PrioritizesArtifactTools() {
        let artifactTool = ToolDefinition(
            name: "artifact_list",
            description: "List artifacts",
            inputSchema: [:]
        )
        let regularTool = ToolDefinition(
            name: "zzz_other",
            description: "Other tool",
            inputSchema: [:]
        )

        let tools = [regularTool, artifactTool]
        let budget = ToolBudget(maxTools: 1)

        let result = ToolBudgetEnforcer.applyBudget(
            to: tools,
            budget: budget,
            hasKnownAttachments: true
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(
            result.first?.name, "artifact_list",
            "Should prioritize artifact tools when attachments present")
    }

    func testToolBudgetEnforcer_PrioritizesCoreTools() {
        let coreTool = ToolDefinition(
            name: "calculator",
            description: "Calculator",
            inputSchema: [:]
        )
        let regularTool = ToolDefinition(
            name: "zzz_other",
            description: "Other tool",
            inputSchema: [:]
        )

        let tools = [regularTool, coreTool]
        let budget = ToolBudget(maxTools: 1)

        let result = ToolBudgetEnforcer.applyBudget(
            to: tools,
            budget: budget,
            hasKnownAttachments: false
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(
            result.first?.name, "calculator",
            "Should prioritize core tools")
    }

    // MARK: - Helpers

    private func createMockTools(count: Int) -> [ToolDefinition] {
        return (0..<count).map { i in
            ToolDefinition(
                name: "tool_\(i)",
                description: "Mock tool \(i)",
                inputSchema: [:]
            )
        }
    }
}
