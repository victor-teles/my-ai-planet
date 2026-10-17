class_name AIProviders
extends RefCounted
## Picks a provider until the AI Settings screen exists (M3).
## MYAIPLANET_AI = offline | anthropic | claude_code | grok_cli.
## Unset: API key, then Claude Code, then Grok CLI, then offline.


static func from_environment() -> AIProvider:
	var anthropic := AnthropicProvider.new(OS.get_environment("ANTHROPIC_API_KEY"))
	match OS.get_environment("MYAIPLANET_AI"):
		"offline":
			return OfflineTemplatesProvider.new()
		"anthropic":
			return anthropic
		"claude_code":
			return ClaudeCodeProvider.new()
		"grok_cli":
			return GrokCliProvider.new()
	if anthropic.is_available():
		return anthropic
	for cli: CliAIProvider in [ClaudeCodeProvider.new(), GrokCliProvider.new()]:
		if cli.is_available():
			return cli
	return OfflineTemplatesProvider.new()
