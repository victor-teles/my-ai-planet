class_name ReplyJson
extends RefCounted
## For models that only promise JSON, or not even that: the schema goes into the prompt, and
## the object is dug out of the reply text. The Oracle still validates it against the schema.


## A prompt paragraph asking for a reply that matches the schema.
static func instructions(schema: Dictionary) -> String:
	return "Reply with only a JSON object, without code fences or any other text. It must match this JSON Schema:\n" + JSON.stringify(JsonSchema.to_wire(schema))


## The JSON object in the reply, even when wrapped in a code fence or a sentence; null if none.
static func parse_object(text: String) -> Variant:
	var reply: Variant = _parse(text)
	if reply is Dictionary:
		return reply
	var start := text.find("{")
	var end := text.rfind("}")
	if start == -1 or end < start:
		return null
	reply = _parse(text.substr(start, end - start + 1))
	return reply if reply is Dictionary else null


## Like JSON.parse_string(), without logging an error for text that isn't JSON.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
