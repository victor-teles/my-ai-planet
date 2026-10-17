class_name AIRequest
extends RefCounted
## One question for an AI provider. Providers must treat it as read-only.

enum Tier { SMALL, MEDIUM, LARGE }

var task: String = "" ## e.g. "prophecy"; the offline provider switches on this
var tier: Tier = Tier.MEDIUM
var system: String = ""
var prompt: String = ""
var schema: Dictionary = {} ## the reply must validate against this (see JsonSchema)
var context: Dictionary = {} ## structured world summary the prompt was built from
var seed_value: int = 0 ## lets offline answers be deterministic without touching the sim's RNG
var max_tokens: int = 16000
var timeout_sec: float = 120.0
