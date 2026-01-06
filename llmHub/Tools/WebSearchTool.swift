//
//  WebSearchTool.swift
//  llmHub
//
//  Web search tool using DuckDuckGo HTML API (no API key required)
//

import Foundation
import OSLog

/// Web Search Tool conforming to the unified Tool protocol.
nonisolated struct WebSearchTool: Tool {
    let name = "web_search"
    let description = """
        Search the web for current information on any topic. \
        Use this tool when you need up-to-date information, \
        need to verify facts, or when the user asks about current events, \
        news, or anything that requires recent information.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "query": ToolProperty(
                    type: .string, description: "The search query to look up on the web"),
                "num_results": ToolProperty(
                    type: .integer, description: "Number of results to return (default: 5, max: 10)"
                ),
                "time_range": ToolProperty(
                    type: .string,
                    description: "Recency filter: d=day, w=week, m=month, y=year",
                    enumValues: ["d", "w", "m", "y"]
                ),
                "region": ToolProperty(
                    type: .string, description: "Region code (e.g., us-en, uk-en)"),
                "safe_search": ToolProperty(
                    type: .boolean, description: "Enable safe search (default: true)"),
            ],
            required: ["query"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = [.networkIO]  // Approximating webAccess -> networkIO
    let weight: ToolWeight = .heavy
    let isCacheable = true

    private let logger = Logger(subsystem: "com.llmhub", category: "WebSearchTool")
    private let session: URLSession

    init(session: URLSession = .shared) {  // Using .shared if LLMURLSession not available
        self.session = session
    }

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let query = arguments.string("query"), !query.isEmpty else {
            throw ToolError.invalidArguments("query is required")
        }

        let numResults = max(1, min(arguments.int("num_results") ?? 5, 10))
        let timeRange = arguments.string("time_range")
        let region = arguments.string("region")
        let safeSearch = arguments.bool("safe_search") ?? true

        context.logger.info("Searching web for: \(query)")  // Use context logger

        do {
            let results = try await searchDuckDuckGo(
                query: query,
                maxResults: numResults,
                timeRange: timeRange,
                region: region,
                safeSearch: safeSearch
            )

            if results.isEmpty {
                return ToolResult.success("No results found for: \(query)")
            }

            return ToolResult.success(formatResults(results, query: query))

        } catch {
            context.logger.error("Web search failed: \(error.localizedDescription)")
            throw ToolError.executionFailed(
                "Search failed: \(error.localizedDescription)", retryable: true)
        }
    }

    // MARK: - DuckDuckGo Search

    private func searchDuckDuckGo(
        query: String,
        maxResults: Int,
        timeRange: String?,
        region: String?,
        safeSearch: Bool
    ) async throws -> [SearchResult] {
        guard var components = URLComponents(string: "https://html.duckduckgo.com/html/") else {
            throw SearchError.invalidQuery
        }

        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let df = timeRange, ["d", "w", "m", "y"].contains(df) {
            queryItems.append(URLQueryItem(name: "df", value: df))
        }
        if let kl = region, !kl.isEmpty {
            queryItems.append(URLQueryItem(name: "kl", value: kl))
        }
        if !safeSearch {
            queryItems.append(URLQueryItem(name: "kp", value: "-2"))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw SearchError.invalidQuery }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36",
            forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw SearchError.requestFailed
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidResponse
        }
        return parseSearchResults(html: html, maxResults: maxResults)
    }

    private func parseSearchResults(html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []
        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]+)">([^<]+)</a>"#
        let descPattern = #"class="result__snippet"[^>]*>([^<]+)"#

        let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [])
        let descRegex = try? NSRegularExpression(pattern: descPattern, options: [])
        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)

        let linkMatches = linkRegex?.matches(in: html, options: [], range: range) ?? []
        let descMatches = descRegex?.matches(in: html, options: [], range: range) ?? []

        for (index, linkMatch) in linkMatches.prefix(maxResults).enumerated() {
            guard linkMatch.numberOfRanges >= 3 else { continue }
            let url = nsHtml.substring(with: linkMatch.range(at: 1))
            let title = nsHtml.substring(with: linkMatch.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            var snippet = ""
            if index < descMatches.count {
                let descMatch = descMatches[index]
                if descMatch.numberOfRanges >= 2 {
                    snippet = nsHtml.substring(with: descMatch.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                }
            }

            // Basic URL cleaning
            var cleanUrl = url
            if let decoded = url.removingPercentEncoding, decoded.contains("uddg=") {
                if let range = decoded.range(of: "uddg=") {
                    cleanUrl =
                        String(decoded[range.upperBound...]).components(separatedBy: "&").first
                        ?? decoded
                }
            }

            results.append(SearchResult(title: title, url: cleanUrl, snippet: snippet))
        }
        return results
    }

    private func formatResults(_ results: [SearchResult], query: String) -> String {
        var output =
            "Web Search Results for: \"\(query)\"\n" + String(repeating: "=", count: 50) + "\n\n"
        for (index, result) in results.enumerated() {
            output += "[\(index + 1)] \(result.title)\n    URL: \(result.url)\n"
            if !result.snippet.isEmpty { output += "    \(result.snippet)\n" }
            output += "\n"
        }
        output += "---\nFound \(results.count) result(s)"
        return output
    }
}

// Supporting Types
struct SearchResult: Sendable {
    let title: String
    let url: String
    let snippet: String
}

enum SearchError: LocalizedError {
    case invalidQuery, requestFailed, invalidResponse, parsingFailed
    var errorDescription: String? {
        switch self {
        case .invalidQuery: return "Invalid search query"
        case .requestFailed: return "Search request failed"
        case .invalidResponse: return "Invalid response"
        case .parsingFailed: return "Failed to parse results"
        }
    }
}
