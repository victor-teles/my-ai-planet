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
