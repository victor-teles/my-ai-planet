class_name AIProvider
extends RefCounted
## Interface every AI backend implements: HTTP APIs, local models, local CLIs, and offline templates.
## complete() is a coroutine: always call it with `await`.


func get_id() -> String:
	return "provider"


func is_available() -> bool:
	return false


func complete(_request: AIRequest) -> AIResponse:
	return AIResponse.failure(get_id(), "Not implemented")
