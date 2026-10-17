class_name AIProviders
extends RefCounted
## Picks a provider until the AI Settings screen exists (M3).
## MYAIPLANET_AI = offline | anthropic | claude_code. Unset: API key, then Claude Code, then offline.


static func from_environment() -> AIProvider:
	var anthropic := AnthropicProvider.new(OS.get_environment("ANTHROPIC_API_KEY"))
	match OS.get_environment("MYAIPLANET_AI"):
		"offline":
			return OfflineTemplatesProvider.new()
		"anthropic":
			return anthropic
		"claude_code":
			return ClaudeCodeProvider.new()
	if anthropic.is_available():
		return anthropic
	var claude_code := ClaudeCodeProvider.new()
	if claude_code.is_available():
		return claude_code
	return OfflineTemplatesProvider.new()
