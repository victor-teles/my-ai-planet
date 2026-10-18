class_name AIProvider
extends RefCounted
## Interface every AI backend implements: HTTP APIs, local models, local CLIs, and offline templates.
## complete() is a coroutine: always call it with `await`.


func get_id() -> String:
	return "provider"


func is_available() -> bool:
	return false


## True for local models and the offline templates: their calls cost the player nothing.
func is_free() -> bool:
	return false


func complete(_request: AIRequest) -> AIResponse:
	return AIResponse.failure(get_id(), "Not implemented")


func supports_streaming() -> bool:
	return false


## Like complete(), but calls on_text(raw_text_so_far: String) as the reply arrives, so long
## text (chronicles) can appear while it is written. Providers that can't stream just complete.
func complete_streaming(request: AIRequest, _on_text: Callable) -> AIResponse:
	return await complete(request)


## The provider that really answers this request: itself, or for a router (AIRouter) the one the
## request's tier goes to. The Oracle caches, counts, charges and skips per answering provider.
func provider_for(_request: AIRequest) -> AIProvider:
	return self


## Every provider behind this one: itself, or a router's distinct providers.
func members() -> Array[AIProvider]:
	var list: Array[AIProvider] = [self]
	return list
