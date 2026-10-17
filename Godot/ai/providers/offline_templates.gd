class_name OfflineTemplatesProvider
extends AIProvider
## Always-available fallback that answers from hand-written templates.
## Deterministic for a given request.seed_value, and never touches the sim's RNG.


func get_id() -> String:
	return "offline"


func is_available() -> bool:
	return true


func complete(request: AIRequest) -> AIResponse:
	match request.task:
		"prophecy":
			return AIResponse.success(get_id(), _prophecy(request))
		"chronicle":
			return AIResponse.success(get_id(), _chronicle(request))
	return AIResponse.failure(get_id(), "Offline templates don't cover task '%s'" % request.task)


func _prophecy(request: AIRequest) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = request.seed_value
	var world := request.context
	var tribes: Array = world.get("tribes", [])
	var population := int(world.get("total_population", 0))
	var first_tribe := String(tribes[0]["name"]) if not tribes.is_empty() else "the people"

	if tribes.size() <= 1:
		return {
			"text": "The %s will not stay one people. Before %d winters pass, the fire will be split in two." % [first_tribe, 40],
			"metric": "tribe_count", "op": ">=", "value": 2, "years_from_now": 40,
		}
	if world.get("in_drought", false) or rng.randf() < 0.5:
		var survivors := maxi(int(population * 0.6), 1)
		return {
			"text": "The sky is closing its hand. Within %d years, hunger will leave fewer than %d souls in the valley." % [30, survivors],
			"metric": "total_population", "op": "<=", "value": survivors, "years_from_now": 30,
		}
	var count := tribes.size() + rng.randi_range(2, 3)
	return {
		"text": "The valley grows crowded. I see %d fires burning on its hills within %d years." % [count, 60],
		"metric": "tribe_count", "op": ">=", "value": count, "years_from_now": 60,
	}


func _chronicle(request: AIRequest) -> Dictionary:
	var record := request.context
	var prophecy: Dictionary = record.get("prophecy", {})
	var came_true := String(prophecy.get("outcome", "")) == "fulfilled"
	var counts := {}
	var miracles := PackedStringArray()
	for event: Dictionary in record.get("events", []):
		var type := String(event["type"])
		counts[type] = int(counts.get(type, 0)) + 1
		if type == "miracle":
			miracles.append(String(event["data"]["miracle"]))

	var causes := PackedStringArray()
	if counts.has("drought_started"):
		causes.append("%d drought%s dried the valley" % [counts["drought_started"], "s" if counts["drought_started"] > 1 else ""])
	if counts.has("famine"):
		causes.append("hunger struck %d time%s" % [counts["famine"], "s" if counts["famine"] > 1 else ""])
	if counts.has("tribe_split"):
		causes.append("%d new tribe%s broke away" % [counts["tribe_split"], "s" if counts["tribe_split"] > 1 else ""])
	if not miracles.is_empty():
		causes.append("the god sent %s" % ", ".join(miracles))
	if causes.is_empty():
		causes.append("the years passed quietly")

	var opening := "As the Oracle foretold, it came to pass." if came_true else "The Oracle spoke, but the world refused the prophecy."
	var middle := "In those years, %s." % "; ".join(causes.slice(0, 3))
	var ending := "Now %d people live in %d tribes." % [int(record.get("population_now", 0)), int(record.get("tribes_now", 0))]
	return {
		"title": "The Prophecy Fulfilled" if came_true else "The Prophecy Broken",
		"text": "%s %s %s" % [opening, middle, ending],
		"causes": Array(causes.slice(0, 3)),
	}
