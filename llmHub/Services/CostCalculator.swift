//
//  CostCalculator.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation

struct CostCalculator {
    func cost(for usage: TokenUsage, pricing: PricingMetadata) -> CostBreakdown {
        let inputCost = Decimal(usage.inputTokens) / 1000 * pricing.inputPer1KUSD
        let outputCost = Decimal(usage.outputTokens) / 1000 * pricing.outputPer1KUSD
        let cachedCost = Decimal(usage.cachedTokens) / 1000 * pricing.inputPer1KUSD
        let totalCost = inputCost + outputCost - cachedCost
        return CostBreakdown(inputCost: inputCost, outputCost: outputCost, cachedCost: cachedCost, totalCost: totalCost)
    }
}
