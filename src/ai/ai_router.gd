class_name AIRouter
extends AIProvider
## Per-tier routing: each model tier (SMALL, MEDIUM, LARGE) can go to its own provider, e.g.
## thoughts to a local Ollama model and chronicles to Claude. The Oracle asks provider_for()
## which provider answers a request, so its cache, usage meter, budget and circuit breaker all
## follow the provider that really answered. A tier without a provider uses the offline templates.

var _routes := {} ## AIRequest.Tier -> AIProvider


## routes: {AIRequest.Tier: AIProvider}. Give tiers that share a provider the same instance.
func _init(routes: Dictionary) -> void:
	for tier: AIRequest.Tier in [AIRequest.Tier.SMALL, AIRequest.Tier.MEDIUM, AIRequest.Tier.LARGE]:
		var routed: AIProvider = routes.get(tier)
		_routes[tier] = routed if routed else OfflineTemplatesProvider.new()


func route(tier: AIRequest.Tier) -> AIProvider:
	return _routes[tier]


func provider_for(request: AIRequest) -> AIProvider:
	return route(request.tier)


## The distinct providers, from the small tier up.
func members() -> Array[AIProvider]:
	var list: Array[AIProvider] = []
	for tier: AIRequest.Tier in _routes:
		if not list.has(_routes[tier]):
			list.append(_routes[tier])
	return list


## The routed providers' ids from the small tier up, e.g. "ollama+anthropic"; one id when every
## tier goes to the same provider. Usage is recorded under the provider that answered.
func get_id() -> String:
	var ids := PackedStringArray()
	for member: AIProvider in members():
		ids.append(member.get_id())
	return "+".join(ids)


func is_available() -> bool:
	return members().all(func(member: AIProvider) -> bool: return member.is_available())


## Free only if every tier is.
func is_free() -> bool:
	return members().all(func(member: AIProvider) -> bool: return member.is_free())


## True if any tier can stream; complete_streaming() just completes on tiers that can't.
func supports_streaming() -> bool:
	return members().any(func(member: AIProvider) -> bool: return member.supports_streaming())


func complete(request: AIRequest) -> AIResponse:
	var routed := route(request.tier)
	return _stamped(await routed.complete(request), routed)


func complete_streaming(request: AIRequest, on_text: Callable) -> AIResponse:
	var routed := route(request.tier)
	if routed.supports_streaming():
		return _stamped(await routed.complete_streaming(request, on_text), routed)
	return _stamped(await routed.complete(request), routed)


## Every response names the provider that wrote it, never the router.
func _stamped(response: AIResponse, routed: AIProvider) -> AIResponse:
	response.provider_id = routed.get_id()
	return response
