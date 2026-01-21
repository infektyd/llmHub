//
//  ToolBudget.swift
//  llmHub
//
//  Tool budget mechanism to cap tool counts/sizes and prioritize tools.
//

import Foundation
import OSLog

/// Policy for tool budget limits
struct ToolBudget {
    /// Maximum number of tools per request (conservative cap)
    let maxTools: Int

    /// Default budget with conservative limits
    static let `default` = ToolBudget(maxTools: 12)

    /// Stricter budget for cost-sensitive scenarios
    static let strict = ToolBudget(maxTools: 8)

    /// Unlimited budget (workhorse mode)
    static let unlimited = ToolBudget(maxTools: Int.max)

    init(maxTools: Int) {
        self.maxTools = maxTools
    }

    /// Resolve budget based on current policy
    static func resolve(for policy: ToolsEnabledPolicy) -> ToolBudget {
        switch policy {
        case .zen:
            return .default
        case .workhorse:
            return .unlimited
        }
    }
}

/// Tool budget enforcement with prioritization
struct ToolBudgetEnforcer {

    #if DEBUG
        private static let logger = Logger(subsystem: "com.llmhub", category: "ToolBudget")
    #endif

    /// Apply budget constraints to a list of tool definitions
    /// - Parameters:
    ///   - tools: The full list of tool definitions
    ///   - budget: The budget to enforce
    ///   - hasKnownAttachments: Whether attachments are present (affects prioritization)
    /// - Returns: Pruned list of tools that fits within budget
    static func applyBudget(
        to tools: [ToolDefinition],
        budget: ToolBudget,
        hasKnownAttachments: Bool = false
    ) -> [ToolDefinition] {
        // If under budget, return all tools
        guard tools.count > budget.maxTools else {
            return tools
        }

        // Prioritize tools
        let prioritized = prioritize(tools: tools, hasKnownAttachments: hasKnownAttachments)

        // Take top N tools
        let pruned = Array(prioritized.prefix(budget.maxTools))

        // Log pruning in DEBUG
        #if DEBUG
            let prunedNames = Set(tools.map { $0.name }).subtracting(pruned.map { $0.name })
            logger.debug(
                "🔧 [ToolBudget] Pruned \(prunedNames.count) tools (budget: \(budget.maxTools)): \(prunedNames.sorted().joined(separator: ", "))"
            )
        #endif

        return pruned
    }

    /// Prioritize tools based on requirements and heuristics
    /// - Parameters:
    ///   - tools: The full list of tool definitions
    ///   - hasKnownAttachments: Whether attachments are present
    /// - Returns: Tools sorted by priority (highest first)
    private static func prioritize(
        tools: [ToolDefinition],
        hasKnownAttachments: Bool
    ) -> [ToolDefinition] {
        // Priority tiers:
        // 1. Attachment-required tools (if attachments present)
        // 2. Core "always needed" tools
        // 3. Other tools (alphabetical for stability)

        let artifactToolNames = ToolRelevanceHeuristics.artifactTools
        let coreToolNames = ToolRelevanceHeuristics.coreTools

        return tools.sorted { lhs, rhs in
            let lhsIsArtifact = artifactToolNames.contains(lhs.name)
            let rhsIsArtifact = artifactToolNames.contains(rhs.name)
            let lhsIsCore = coreToolNames.contains(lhs.name)
            let rhsIsCore = coreToolNames.contains(rhs.name)

            // Tier 1: Artifact tools when attachments present
            if hasKnownAttachments {
                if lhsIsArtifact != rhsIsArtifact {
                    return lhsIsArtifact
                }
            }

            // Tier 2: Core tools
            if lhsIsCore != rhsIsCore {
                return lhsIsCore
            }

            // Tier 3: Alphabetical for stable ordering
            return lhs.name < rhs.name
        }
    }
}
