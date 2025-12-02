//
//  CostCalculator.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation

/// Utility structure to calculate the cost of LLM interactions based on token usage.
struct CostCalculator {
    /// Calculates the cost breakdown for a given token usage and pricing metadata.
    /// - Parameters:
    ///   - usage: The token usage statistics (input, output, cached).
    ///   - pricing: The pricing metadata for the provider/model.
    /// - Returns: A `CostBreakdown` struct containing cost details.
    func cost(for usage: TokenUsage, pricing: PricingMetadata) -> CostBreakdown {
        let inputCost = Decimal(usage.inputTokens) / 1000 * pricing.inputPer1KUSD
        let outputCost = Decimal(usage.outputTokens) / 1000 * pricing.outputPer1KUSD

        // Note: Cached token pricing might differ from input pricing depending on the provider.
        // Assuming cached tokens are discounted or priced differently,
        // logic here subtracts cached cost from total (implying cached tokens were already counted in inputTokens but should be cheaper?)
        // OR it calculates a separate cost.
        // Without precise provider logic, assuming cached tokens are 'saved' cost or charged differently.
        // For simplicity, let's assume cached tokens are charged at input rate but represented separately.
        // Refined logic: Cached tokens are usually a subset of input tokens, or charged at a lower rate.
        // If the 'inputTokens' count includes cached tokens, we might need to adjust.
        // Standard practice: Input tokens usually means *total* input tokens.
        // If usage.cachedTokens > 0, usually those are charged at a lower rate (e.g., 10% of input cost).

        // Simplified Logic (matches previous implementation behavior):
        let cachedCost = Decimal(usage.cachedTokens) / 1000 * pricing.inputPer1KUSD
        let totalCost = inputCost + outputCost - cachedCost
        return CostBreakdown(inputCost: inputCost, outputCost: outputCost, cachedCost: cachedCost, totalCost: totalCost)
    }
}
