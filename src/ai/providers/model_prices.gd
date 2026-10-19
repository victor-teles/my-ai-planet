class_name ModelPrices
extends RefCounted
## What known cloud models charge, so the usage meter can show what a call cost the player.
## USD per million [input, output] tokens, standard tier, from the providers' price pages
## (checked 2026-10). Unknown models cost 0: better no estimate than a wrong one.

const PER_MILLION := {
	# Anthropic
	"claude-haiku-5-5": [0.10, 0.50],
	"claude-sonnet-5-5": [2.0, 10.0],
	"claude-opus-5-5": [4.0, 20.0],
	# OpenAI
	"gpt-6-luna": [0.10, 0.50],
	"gpt-6-sol": [2.0, 10.0],
	"gpt-6.1-sol": [2.0, 10.0],
	"gpt-6-astra": [10.0, 50.0],
	"gpt-5.6-luna": [0.20, 1.20],
	"gpt-5.6-terra": [2.0, 12.0],
	"gpt-5-mini": [0.25, 2.0],
	"gpt-5-nano": [0.05, 0.40],
	# Google
	"gemini-3.5-flash-lite": [0.30, 2.50],
	"gemini-3.1-flash-lite": [0.25, 1.50],
	"gemini-3.8-flash": [0.75, 3.75],
	"gemini-3.6-flash": [0.75, 3.75],
	"gemini-4-argon": [2.0, 10.0],
	"gemini-3.1-pro-preview": [2.0, 12.0],
	"gemini-2.5-flash-lite": [0.10, 0.40],
	"gemini-2.5-flash": [0.30, 2.50],
	"gemini-2.5-pro": [1.25, 10.0],
}


static func estimate(model: String, input_tokens: int, output_tokens: int) -> float:
	var price: Array = PER_MILLION.get(model, [0.0, 0.0])
	return (input_tokens * float(price[0]) + output_tokens * float(price[1])) / 1_000_000.0
