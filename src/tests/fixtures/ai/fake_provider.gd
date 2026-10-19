extends AIProvider
## A scripted AI provider for tests: answers with `reply` (or fails), costs `cost` a call, can be
## slow (answers only once `released` is emitted), and can stream its reply in `chunks` pieces.

signal released

var id := "fake"
var reply: Dictionary = {}
var fail := false
var free := false
var cost := 0.0
var slow := false
var streaming := false
var chunks := 5
var calls := 0
var last_request: AIRequest


func _init(fake_reply: Dictionary = {}, provider_id: String = "fake") -> void:
	reply = fake_reply
	id = provider_id


func get_id() -> String:
	return id


func is_available() -> bool:
	return true


func is_free() -> bool:
	return free


func supports_streaming() -> bool:
	return streaming


func complete(request: AIRequest) -> AIResponse:
	calls += 1
	last_request = request
	if slow:
		await released
	if fail:
		return AIResponse.failure(id, "scripted failure")
	var response := AIResponse.success(id, reply.duplicate(true))
	response.cost_usd = cost
	response.input_tokens = 100
	response.output_tokens = 20
	return response


@warning_ignore("integer_division")
func complete_streaming(request: AIRequest, on_text: Callable) -> AIResponse:
	var raw := JSON.stringify(reply)
	for k: int in chunks:
		on_text.call(raw.left(raw.length() * (k + 1) / chunks))
	return await complete(request)
