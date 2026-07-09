# Provider Compatibility Matrix

## Overview
The agent-identity-architecture skill is provider-agnostic. All scripts are plain Python/Bash using only stdlib.

## Provider Support

| Provider | Compatibility | Notes |
|----------|---------------|-------|
| **Claude (Anthropic)** | Full | MCP servers, tool use, function calling |
| **OpenAI / ChatGPT** | Full | Function calling, Actions, Assistants API |
| **Mistral / Le Chat** | Full | Tool calling, script execution |
| **Gemini (Google)** | Full | Extensions, Vertex AI, function calling |
| **Hermes (Nous)** | Full | Tool-use fine-tuned, native MCP |
| **GitHub Copilot** | Partial | Code generation; use external runner for scripts |
| **Any LLM + tools** | Full | Scripts are plain Python, provider-independent |

## Implementation Notes

- All identity scripts (`enforcer_daemon.py`, `agent_runtime.py`, `memory_curator.py`) use Python stdlib only
- No provider-specific SDKs required
- Works with any LLM that can execute shell commands or call functions
- MCP servers can wrap the enforcer/agent runtime for provider integration
- OpenClaw gateway provides multi-agent orchestration layer