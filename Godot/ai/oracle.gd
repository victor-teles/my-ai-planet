class_name Oracle
extends RefCounted
## Builds AI requests from the world and turns AI replies into validated game objects.
## The AI only proposes: anything that fails the schema or the sim's rules falls back to offline templates.

const PROPHECY_PROMPT := "prophecy.v1"
const CHRONICLE_PROMPT := "chronicle.v1"
const MAX_CHRONICLE_EVENTS := 40

var provider: AIProvider
var fallback: AIProvider = OfflineTemplatesProvider.new()
## The last response from any provider, for the debug overlay.
var last_response: AIResponse
var calls := 0
var cost_usd := 0.0


func _init(ai_provider: AIProvider) -> void:
	provider = ai_provider


func request_prophecy(state: WorldState) -> Prophecy:
	var context := state.summarize()
	var request := _request("prophecy", PROPHECY_PROMPT, context, "world", state)
	var accept := func(reply: Dictionary) -> Variant: return Prophecy.from_proposal(reply, state)
	return await _ask(request, accept)


## Returns {"title", "text", "causes"} telling how the prophecy came true or broke.
func request_chronicle(state: WorldState, prophecy: Prophecy) -> Dictionary:
	var events: Array[Dictionary] = []
	for event: Dictionary in state.events:
		if int(event["tick"]) >= prophecy.start_tick and int(event["tick"]) <= prophecy.resolved_tick:
			events.append({"year": WorldState.year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
	var record := {
		"prophecy": {
			"text": prophecy.text,
			"condition": "%s %s %d before year %d" % [prophecy.metric, prophecy.op, prophecy.target, prophecy.deadline_year],
			"outcome": "fulfilled" if prophecy.status == Prophecy.Status.FULFILLED else "broken",
			"made_in_year": WorldState.year_of(prophecy.start_tick),
			"resolved_in_year": WorldState.year_of(prophecy.resolved_tick),
		},
		"events": events.slice(maxi(events.size() - MAX_CHRONICLE_EVENTS, 0)),
		"population_now": state.total_population(),
		"tribes_now": state.tribe_count(),
		"world_now": state.summarize(0),
	}
	var request := _request("chronicle", CHRONICLE_PROMPT, record, "record", state)
	var accept := func(reply: Dictionary) -> Variant: return reply
	var chronicle: Variant = await _ask(request, accept)
	return chronicle if chronicle is Dictionary else {}


func _request(task: String, prompt_name: String, context: Dictionary, placeholder: String, state: WorldState) -> AIRequest:
	var request := AIRequest.new()
	request.task = task
	request.tier = AIRequest.Tier.LARGE
	request.context = context
	request.schema = AIAssets.schema(task)
	request.system = AIAssets.prompt(prompt_name + ".system", {"tone": state.tone()})
	request.prompt = AIAssets.prompt(prompt_name + ".user", {placeholder: JSON.stringify(context, "  ")})
	request.seed_value = hash([state.seed_value, state.tick, task])
	return request


## Asks the provider, then the fallback. `accept` turns a schema-valid reply into the
## result, or returns null to reject it under the sim's rules.
func _ask(request: AIRequest, accept: Callable) -> Variant:
	for ai: AIProvider in [provider, fallback] if provider != fallback else [provider]:
		var response := await ai.complete(request)
		last_response = response
		calls += 1
		cost_usd += response.cost_usd
		if not response.ok:
			push_warning("Oracle: %s failed on %s: %s" % [ai.get_id(), request.task, response.error])
			continue
		var errors := JsonSchema.validate(response.data, request.schema)
		if not errors.is_empty():
			push_warning("Oracle: %s %s reply broke the schema: %s" % [ai.get_id(), request.task, "; ".join(errors)])
			continue
		var result: Variant = accept.call(response.data)
		if result == null:
			push_warning("Oracle: %s proposed a %s the sim rejected: %s" % [ai.get_id(), request.task, response.data])
			continue
		return result
	return null
