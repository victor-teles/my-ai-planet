class_name Oracle
extends RefCounted
## Builds AI requests from the world and turns AI replies into validated game objects.
## The AI only proposes: anything that fails the schema or the sim's rules falls back to offline templates.

const PROPHECY_PROMPT := "prophecy.v1"

var provider: AIProvider
var fallback: AIProvider = OfflineTemplatesProvider.new()
var tone: int = 2 ## 1 gentle fable .. 5 grim chronicle; driven by player Disposition later
## The last response from any provider, for the debug overlay.
var last_response: AIResponse


func _init(ai_provider: AIProvider) -> void:
	provider = ai_provider


func request_prophecy(state: WorldState) -> Prophecy:
	var request := AIRequest.new()
	request.task = "prophecy"
	request.tier = AIRequest.Tier.LARGE
	request.context = state.summarize()
	request.schema = AIAssets.schema("prophecy")
	request.system = AIAssets.prompt(PROPHECY_PROMPT + ".system", {"tone": tone})
	request.prompt = AIAssets.prompt(PROPHECY_PROMPT + ".user", {"world": JSON.stringify(request.context, "  ")})
	request.seed_value = hash([state.seed_value, state.tick])

	var prophecy := await _try_prophecy(provider, request, state)
	if prophecy == null and provider != fallback:
		prophecy = await _try_prophecy(fallback, request, state)
	return prophecy


func _try_prophecy(ai: AIProvider, request: AIRequest, state: WorldState) -> Prophecy:
	var response := await ai.complete(request)
	last_response = response
	if not response.ok:
		push_warning("Oracle: %s failed: %s" % [ai.get_id(), response.error])
		return null
	var errors := JsonSchema.validate(response.data, request.schema)
	if not errors.is_empty():
		push_warning("Oracle: %s reply broke the schema: %s" % [ai.get_id(), "; ".join(errors)])
		return null
	var prophecy := Prophecy.from_proposal(response.data, state)
	if prophecy == null:
		push_warning("Oracle: %s proposed a prophecy the sim rejected: %s" % [ai.get_id(), response.data])
	return prophecy
