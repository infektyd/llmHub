//
//  WebSearchTool.swift
//  llmHub
//
//  Web search tool using DuckDuckGo HTML API (no API key required)
//

import Foundation
import OSLog

/// Web Search Tool conforming to the Tool protocol
/// Searches the web using DuckDuckGo and returns results
struct WebSearchTool: Tool {
    nonisolated let id = "web_search"
    nonisolated let name = "web_search"
    nonisolated let description = """
        Search the web for current information on any topic. \
        Use this tool when you need up-to-date information, \
        need to verify facts, or when the user asks about current events, \
        news, or anything that requires recent information.
        """

    nonisolated var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "The search query to look up on the web",
                ],
                "num_results": [
                    "type": "integer",
                    "description": "Number of results to return (default: 5, max: 10)",
                ],
            ],
            "required": ["query"],
        ]
    }

    private let logger = Logger(subsystem: "com.llmhub", category: "WebSearchTool")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func execute(input: [String: Any]) async throws -> String {
        guard let query = input["query"] as? String, !query.isEmpty else {
            throw ToolError.invalidInput
        }

        let numResults = min(input["num_results"] as? Int ?? 5, 10)

        logger.info("Searching web for: \(query)")

        do {
            let results = try await searchDuckDuckGo(query: query, maxResults: numResults)

            if results.isEmpty {
                return "No results found for: \(query)"
            }

            return formatResults(results, query: query)
        } catch {
            logger.error("Web search failed: \(error)")
            throw ToolError.executionFailed("Search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - DuckDuckGo Search

    private func searchDuckDuckGo(query: String, maxResults: Int) async throws -> [SearchResult] {
        // Use DuckDuckGo HTML search (no API key required)
        guard
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encodedQuery)")
        else {
            throw SearchError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

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

    // MARK: - HTML Parsing

    private func parseSearchResults(html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        // Parse DuckDuckGo HTML results
        // Results are in <div class="result"> blocks
        // Parse DuckDuckGo HTML results
        // Results are in <div class="result"> blocks

        // Alternative simpler patterns for DuckDuckGo's structure
        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]+)">([^<]+)</a>"#
        let descPattern = #"class="result__snippet"[^>]*>([^<]+)"#

        // Try to extract using simpler regex
        let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [])
        let descRegex = try? NSRegularExpression(pattern: descPattern, options: [])

        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)

        // Find all links
        let linkMatches = linkRegex?.matches(in: html, options: [], range: range) ?? []
        let descMatches = descRegex?.matches(in: html, options: [], range: range) ?? []

        for (index, linkMatch) in linkMatches.prefix(maxResults).enumerated() {
            guard linkMatch.numberOfRanges >= 3 else { continue }

            let urlRange = linkMatch.range(at: 1)
            let titleRange = linkMatch.range(at: 2)

            let url = nsHtml.substring(with: urlRange)
            let title = nsHtml.substring(with: titleRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x27;", with: "'")

            // Try to get corresponding snippet
            var snippet = ""
            if index < descMatches.count {
                let descMatch = descMatches[index]
                if descMatch.numberOfRanges >= 2 {
                    snippet = nsHtml.substring(with: descMatch.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&#x27;", with: "'")
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                }
            }

            // Clean up the URL (DuckDuckGo sometimes uses redirect URLs)
            var cleanUrl = url
            if url.contains("uddg=") {
                if let range = url.range(of: "uddg="),
                    let decoded = url[range.upperBound...].removingPercentEncoding
                {
                    cleanUrl = decoded.components(separatedBy: "&").first ?? decoded
                }
            }

            results.append(
                SearchResult(
                    title: title,
                    url: cleanUrl,
                    snippet: snippet
                ))
        }

        return results
    }

    // MARK: - Formatting

    private func formatResults(_ results: [SearchResult], query: String) -> String {
        var output = "Web Search Results for: \"\(query)\"\n"
        output += String(repeating: "=", count: 50) + "\n\n"

        for (index, result) in results.enumerated() {
            output += "[\(index + 1)] \(result.title)\n"
            output += "    URL: \(result.url)\n"
            if !result.snippet.isEmpty {
                output += "    \(result.snippet)\n"
            }
            output += "\n"
        }

        output += "---\n"
        output += "Found \(results.count) result(s)"

        return output
    }
}

// MARK: - Supporting Types

struct SearchResult {
    let title: String
    let url: String
    let snippet: String
}

enum SearchError: LocalizedError {
    case invalidQuery
    case requestFailed
    case invalidResponse
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .invalidQuery: return "Invalid search query"
        case .requestFailed: return "Search request failed"
        case .invalidResponse: return "Invalid response from search engine"
        case .parsingFailed: return "Failed to parse search results"
        }
    }
}
