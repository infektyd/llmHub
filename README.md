# llmHub

llmHub is a native macOS and iOS application for AI agent workflows. It uses a modular Brain/Hand/Loop architecture, a flat UI design, Model Context Protocol (MCP) support, and a tool system.

## Features

- Support for multiple LLM providers (OpenAI, Anthropic, Google, Mistral, xAI, OpenRouter)
- Canvas-based user interface
- Tool system with permission controls
- Model and provider persistence across sessions
- Context management with token estimation
- Model Context Protocol (MCP) support for external tools

## Architecture

llmHub follows the Brain/Hand/Loop design:

- Brain: LLM provider implementations
- Hand: Tool implementations
- Loop: Chat orchestration layer

## Installation and Setup

See platform-specific documentation in Docs/Platform/.

## Documentation

Public APIs include docstrings. New code should include docstrings following Swift documentation standards.

## License

See the LICENSE file.
