class_name Oracle
extends RefCounted
## Builds AI requests from the world and turns AI replies into validated game objects.
## The AI only proposes: anything that fails the schema, the content ceiling (ContentGuard) or the
## sim's rules falls back to offline templates. On the way, replies are cached (AICache), identical
## requests in flight share one call, a failed call is retried once, a provider that keeps failing
## is skipped for a while (CircuitBreaker), and once the session budget is spent (AIBudget) the
## Oracle stays offline. Everything is counted for the usage meter (see usage()). The provider may
## be an AIRouter sending each model tier to its own provider: all of the above is kept per
## provider that really answers (AIProvider.provider_for()).

signal usage_changed
## The session dropped to the offline templates (the budget is spent), until the settings change.
signal went_offline(reason: String)

const MAX_CHRONICLE_EVENTS := 40
const MAX_DESTINY_EVENTS := 60
const ATTEMPTS := 2 ## a failed or rejected call is retried once before the fallback answers
const GENTLE_TONE := 2 ## Gentle Mode never writes darker than this
const DEFAULT_PACING := "keep the story moving" ## when no DramaManager hint is given

var provider: AIProvider
var fallback: AIProvider = OfflineTemplatesProvider.new()
## The last response from any provider, for the debug overlay.
var last_response: AIResponse
var calls := 0 ## provider calls made (cache hits and shared calls aren't calls)
var cost_usd := 0.0
var cache: AICache
var budget := AIBudget.from_environment()
var breaker := CircuitBreaker.new()
var meter := AIUsage.new()
## Gentle Mode caps the tone at GENTLE_TONE, tells the prompts, and checks replies against the
## stricter list. MYAIPLANET_GENTLE=1 turns it on; the settings screen can flip it any time.
var gentle := OS.get_environment("MYAIPLANET_GENTLE") == "1"
## task -> prompt version (e.g. {"prophecy": "v1"}), overriding the manifest to compare or roll back.
var prompt_versions := {}

var _in_flight := {} ## cache key -> InFlight
var _dropped_reason := ""


## Tests pass their own cache; by default the cache is kept on disk, except when headless.
func _init(ai_provider: AIProvider, response_cache: AICache = null) -> void:
	provider = ai_provider
	var persist := "" if DisplayServer.get_name() == "headless" else AICache.DISK_DIR
	cache = response_cache if response_cache else AICache.new(256, persist)


## pacing: a few words on what the story needs now (DramaManager.pacing_hint()).
func request_prophecy(state: WorldState, pacing: String = "") -> Prophecy:
	var accept := func(reply: Dictionary) -> Variant: return Prophecy.from_proposal(reply, state)
	return await _ask(prophecy_request(state, pacing), accept)


## pacing: a few words on what the story needs now (DramaManager.pacing_hint()).
func request_dilemma(state: WorldState, pacing: String = "") -> Dilemma:
	var accept := func(reply: Dictionary) -> Variant: return Dilemma.from_proposal(reply, state)
	return await _ask(dilemma_request(state, pacing), accept)


## What a citizen (by index) is thinking, in their own words.
func request_thought(state: WorldState, c: int) -> String:
	var accept := func(reply: Dictionary) -> Variant:
		var thought := String(reply["thought"]).strip_edges()
		return thought if thought else null
	var thought: Variant = await _ask(thought_request(state, c), accept)
	return thought if thought is String else ""


## The offline thought, right away, to show while a real AI writes a better one.
func offline_thought(state: WorldState, c: int) -> String:
	return String(OfflineTemplatesProvider.new().thought(thought_request(state, c)))


## Returns {"title", "text", "causes"} telling how the prophecy came true or broke. With on_text,
## the story is streamed: on_text(text_so_far: String) gets the readable text as the provider writes
## it (when it can stream), and always the final accepted text last.
func request_chronicle(state: WorldState, prophecy: Prophecy, on_text: Callable = Callable()) -> Dictionary:
	var accept := func(reply: Dictionary) -> Variant: return reply
	var chronicle: Variant = await _ask(chronicle_request(state, prophecy), accept, on_text)
	return _story(chronicle, on_text)


## Returns {"title", "text", "causes"}: the last chapter of the island, once it has met its destiny.
## on_text streams it like request_chronicle().
func request_destiny(state: WorldState, on_text: Callable = Callable()) -> Dictionary:
	var accept := func(reply: Dictionary) -> Variant: return reply
	var chapter: Variant = await _ask(destiny_request(state), accept, on_text)
	return _story(chapter, on_text)


## The tone the prompts get: the world's, capped in Gentle Mode.
func tone_for(state: WorldState) -> int:
	return mini(state.tone(), GENTLE_TONE) if gentle else state.tone()


# --- Requests (public so the golden tests build exactly what the game sends) ---------

func prophecy_request(state: WorldState, pacing: String = "") -> AIRequest:
	return _request("prophecy", state.summarize(), state, pacing)


func dilemma_request(state: WorldState, pacing: String = "") -> AIRequest:
	return _request("dilemma", state.summarize(), state, pacing)


func thought_request(state: WorldState, c: int) -> AIRequest:
	var request := _request("thought", People.describe(state, c), state)
	request.seed_value = hash([state.seed_value, state.person_ids[c], state.year()])
	return request


func chronicle_request(state: WorldState, prophecy: Prophecy) -> AIRequest:
	var events: Array[Dictionary] = []
	var daily_life := {}
	for event: Dictionary in state.events:
		if int(event["tick"]) < prophecy.start_tick or int(event["tick"]) > prophecy.resolved_tick:
			continue
		if EventText.is_major(event):
			events.append({"year": WorldState.year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
		else:
			daily_life[event["type"]] = int(daily_life.get(event["type"], 0)) + 1
	var record := {
		"prophecy": {
			"text": prophecy.text,
			"condition": "%s %s %d before year %d" % [prophecy.metric, prophecy.op, prophecy.target, prophecy.deadline_year],
			"outcome": "fulfilled" if prophecy.status == Prophecy.Status.FULFILLED else "broken",
			"made_in_year": WorldState.year_of(prophecy.start_tick),
			"resolved_in_year": WorldState.year_of(prophecy.resolved_tick),
		},
		"events": events.slice(maxi(events.size() - MAX_CHRONICLE_EVENTS, 0)),
		"daily_life": daily_life,
		"population_now": state.total_population(),
		"tribes_now": state.tribe_count(),
		"world_now": state.summarize(0),
	}
	return _request("chronicle", record, state)


func destiny_request(state: WorldState) -> AIRequest:
	var kind := String(state.destiny.get("kind", ""))
	var tribe := String(state.destiny.get("tribe", ""))
	var t := state.tribe_index(tribe)
	# The turns that bent the island's history: politics, ages, wars and the god, oldest first.
	var turns: Array[Dictionary] = []
	var counts := {}
	for event: Dictionary in state.events:
		var category := EventText.category(event)
		if EventText.is_major(event) and category in ["politics", "conflict", "god", "discovery"] and String(event["type"]) not in ["tech_spread", "election"]:
			turns.append({"year": WorldState.year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
		counts[event["type"]] = int(counts.get(event["type"], 0)) + 1
	var record := {
		"destiny": {"kind": kind, "name": DestinySystem.name_of(kind), "meaning": String(DestinySystem.KINDS.get(kind, {}).get("text", "")), "year": int(state.destiny.get("year", state.year()))},
		"realm": {"tribe": tribe, "society": Society.summary(state, t) if t != -1 else {}, "vassals": Society.vassals_of(state, tribe)},
		"events": turns.slice(maxi(turns.size() - MAX_DESTINY_EVENTS, 0)),
		"history_counts": counts,
		"god": state.disposition(),
		"world_now": state.summarize(0),
	}
	return _request("destiny", record, state)


## pacing fills the {pacing} placeholder of the prompts that have one (DEFAULT_PACING when empty).
func _request(task: String, context: Dictionary, state: WorldState, pacing: String = "") -> AIRequest:
	var request := AIRequest.new()
	request.task = task
	request.prompt_version = String(prompt_versions.get(task, AIPrompts.version(task)))
	request.tier = budget.route(task)
	request.context = context
	request.schema = AIAssets.schema(String(AIPrompts.entry(task)["schema"]))
	var values := {"tone": tone_for(state), "disposition": state.disposition_text(), "gentle": gentle, "pacing": pacing if pacing else DEFAULT_PACING}
	request.system = AIPrompts.system(task, request.prompt_version, values)
	request.prompt = AIPrompts.user(task, request.prompt_version, context)
	request.seed_value = hash([state.seed_value, state.tick, task])
	return request


# --- Usage --------------------------------------------------------------------------

## True once the session has dropped to the offline templates, or has no AI at all.
func is_offline() -> bool:
	return not _dropped_reason.is_empty() or _no_ai()


## True if this task is answered by the offline templates right now (its tier routes there, the
## session dropped offline, or its provider is being skipped): no point waiting for a better answer.
func offline_for(task: String) -> bool:
	var probe := AIRequest.new()
	probe.tier = budget.route(task)
	var ai := provider.provider_for(probe)
	return not _dropped_reason.is_empty() or _is_offline(ai) or not breaker.allows(ai.get_id())


## Swaps the provider (the AI Settings screen) without restarting the game.
func set_provider(ai: AIProvider) -> void:
	provider = ai
	reconsider()


## Call after changing the provider or the budget's caps: a session that dropped offline because
## the budget ran out comes back once the budget allows more.
func reconsider() -> void:
	if _dropped_reason and not budget.exhausted():
		_dropped_reason = ""
	usage_changed.emit()


## Why the Oracle answers from the offline templates right now, or "" if it doesn't: no provider,
## the budget is spent, or the circuit breaker is skipping a failing provider for a while.
func offline_reason() -> String:
	if _no_ai():
		return "no AI provider: using the offline templates"
	if _dropped_reason:
		return _dropped_reason
	for member: AIProvider in provider.members():
		var id := member.get_id()
		if not _is_offline(member) and breaker.is_open(id):
			return "%s failed %d times in a row: skipped for %ds" % [id, breaker.failures(id), ceili(breaker.seconds_left(id))]
	return ""


## For the usage meter: AIUsage.report() ({"providers", "tasks", "total"}, each stats being
## {"calls", "failures", "cache_hits", "input_tokens", "output_tokens", "cost_usd", "avg_latency_ms"})
## plus "offline" (bool), "offline_reason", "budget" (AIBudget.report()), "cache" and "gentle".
func usage() -> Dictionary:
	var report := meter.report()
	report["offline"] = not offline_reason().is_empty()
	report["offline_reason"] = offline_reason()
	report["budget"] = budget.report()
	report["cache"] = {"hits": cache.hits, "misses": cache.misses, "size": cache.size()}
	report["gentle"] = gentle
	return report


# --- Asking -------------------------------------------------------------------------

## Asks the provider (or the cache), then the fallback. `accept` turns a valid reply into the
## result, or returns null to reject it under the sim's rules.
func _ask(request: AIRequest, accept: Callable, on_text: Callable = Callable()) -> Variant:
	var ai := provider.provider_for(request)
	if not _is_offline(ai):
		var result: Variant = await _ask_provider(ai, request, accept, on_text)
		if result != null:
			return result
	return await _ask_fallback(request, accept)


func _ask_provider(ai: AIProvider, request: AIRequest, accept: Callable, on_text: Callable) -> Variant:
	var id := ai.get_id()
	var key := AICache.key(id, request)
	var cached := cache.lookup(key)
	if not cached.is_empty():
		var reused: Variant = _judge(id, request, cached, accept)
		if reused != null:
			meter.record_hit(id, request.task)
			last_response = AIResponse.success(id, cached)
			last_response.cached = true
			usage_changed.emit()
			return reused
		cache.forget(key)
	for _attempt: int in ATTEMPTS:
		if not _may_ask(ai):
			break
		var shared := _in_flight.has(key)
		var response := await _call(ai, request, key, on_text)
		if not response.ok:
			push_warning("Oracle: %s failed on %s: %s" % [id, request.task, response.error])
		var result: Variant = _judge(id, request, response.data, accept) if response.ok else null
		if shared:
			if result != null:
				return result
			continue
		if result != null:
			breaker.success(id)
			cache.store(key, response.data)
			return result
		breaker.failure(id)
		meter.record_failure(id, request.task)
		usage_changed.emit()
	return null


## One provider call. A caller asking exactly what another is already waiting for shares its call.
func _call(ai: AIProvider, request: AIRequest, key: String, on_text: Callable) -> AIResponse:
	if _in_flight.has(key):
		var waiting: InFlight = _in_flight[key]
		meter.record_hit(ai.get_id(), request.task)
		await waiting.done
		return waiting.response
	var flight := InFlight.new()
	_in_flight[key] = flight
	var response := await _complete(ai, request, on_text)
	_in_flight.erase(key)
	budget.charge(response, _is_free(ai))
	if budget.exhausted() and not _is_free(ai) and _dropped_reason.is_empty():
		_dropped_reason = "budget: " + budget.why_exhausted()
		push_warning("Oracle: going offline until the budget allows more (%s)" % _dropped_reason)
		went_offline.emit(_dropped_reason)
	flight.response = response
	flight.done.emit()
	return response


func _ask_fallback(request: AIRequest, accept: Callable) -> Variant:
	var response := await _complete(fallback, request, Callable())
	var result: Variant = null
	if response.ok:
		result = _judge(fallback.get_id(), request, response.data, accept)
	else:
		push_warning("Oracle: %s failed on %s: %s" % [fallback.get_id(), request.task, response.error])
	if result == null:
		meter.record_failure(fallback.get_id(), request.task)
		usage_changed.emit()
	return result


func _complete(ai: AIProvider, request: AIRequest, on_text: Callable) -> AIResponse:
	var started := Time.get_ticks_msec()
	var response: AIResponse
	if on_text.is_valid() and ai.supports_streaming():
		response = await ai.complete_streaming(request, _story_stream(on_text))
	else:
		response = await ai.complete(request)
	response.latency_ms = Time.get_ticks_msec() - started
	if response.provider_id.is_empty():
		response.provider_id = ai.get_id()
	last_response = response
	calls += 1
	cost_usd += response.cost_usd
	meter.record_call(ai.get_id(), request.task, response)
	usage_changed.emit()
	return response


## Checks a reply against the schema, the content ceiling and then the sim's rules (accept).
func _judge(id: String, request: AIRequest, reply: Dictionary, accept: Callable) -> Variant:
	var errors := JsonSchema.validate(reply, request.schema)
	if not errors.is_empty():
		push_warning("Oracle: %s %s reply broke the schema: %s" % [id, request.task, "; ".join(errors)])
		return null
	var flagged := ContentGuard.check(reply, gentle)
	if not flagged.is_empty():
		push_warning("Oracle: %s %s reply crossed the content ceiling: %s" % [id, request.task, "; ".join(flagged)])
		return null
	var result: Variant = accept.call(reply)
	if result == null:
		push_warning("Oracle: %s proposed a %s the sim rejected: %s" % [id, request.task, reply])
	return result


func _may_ask(ai: AIProvider) -> bool:
	return breaker.allows(ai.get_id()) and (_is_free(ai) or (_dropped_reason.is_empty() and not budget.exhausted()))


## Every tier answers from the offline templates.
func _no_ai() -> bool:
	return provider.members().all(func(member: AIProvider) -> bool: return _is_offline(member))


func _is_offline(ai: AIProvider) -> bool:
	return ai == fallback or ai is OfflineTemplatesProvider


func _is_free(ai: AIProvider) -> bool:
	return ai.is_free() or ai is OfflineTemplatesProvider


## Turns the raw streamed reply into its readable story for on_text, as long as it stays clean.
func _story_stream(on_text: Callable) -> Callable:
	var shown := [""]
	return func(raw: String) -> void:
		var story := PartialJson.string_field(raw, "text")
		if story.length() > String(shown[0]).length() and ContentGuard.check_text(story, gentle).is_empty():
			shown[0] = story
			on_text.call(story)


## A chronicle or chapter from _ask, or {}; on_text gets its final text.
func _story(reply: Variant, on_text: Callable) -> Dictionary:
	var story: Dictionary = reply if reply is Dictionary else {}
	if on_text.is_valid() and story.has("text"):
		on_text.call(String(story["text"]))
	return story


## A provider call that others asking the same thing can wait for.
class InFlight:
	extends RefCounted
	signal done
	var response: AIResponse
