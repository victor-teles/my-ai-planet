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
		"dilemma":
			return AIResponse.success(get_id(), _dilemma(request))
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


func _dilemma(request: AIRequest) -> Dictionary:
	var world := request.context
	var tribes: Array = world.get("tribes", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = request.seed_value
	if tribes.is_empty():
		return {}
	# The hungriest tribe and the largest tribe drive most dilemmas.
	var hungry: Dictionary = tribes[0]
	var largest: Dictionary = tribes[0]
	for tribe: Dictionary in tribes:
		if float(tribe["food_months"]) < float(hungry["food_months"]):
			hungry = tribe
		if int(tribe["population"]) > int(largest["population"]):
			largest = tribe

	if world.get("in_drought", false):
		return {
			"title": "The Last Well",
			"situation": "The drought has dried every spring but one, and the %s guard it. Other tribes are coming with empty jars." % largest["name"],
			"tribe": largest["name"],
			"choices": [
				{"label": "Make them share the water", "hint": "Everyone drinks a little. The %s will remember what they gave up." % largest["name"],
					"effects": [{"type": "food", "tribe": largest["name"], "amount": -2}, {"type": "kindness", "tribe": "", "amount": 1}]},
				{"label": "Let them keep it", "hint": "The %s will thrive. The others may not forgive." % largest["name"],
					"effects": [{"type": "food", "tribe": largest["name"], "amount": 2}, {"type": "kindness", "tribe": "", "amount": -1}]},
				{"label": "Spend your power to call the rain", "hint": "It will cost you dearly.",
					"effects": [{"type": "rain", "tribe": "", "amount": 6}, {"type": "influence", "tribe": "", "amount": -3}]},
			],
		}
	if float(hungry["food_months"]) < 1.5 and tribes.size() > 1:
		var neighbor: Dictionary = largest if largest != hungry else tribes[(tribes.find(hungry) + 1) % tribes.size()]
		return {
			"title": "Empty Bellies",
			"situation": "The %s are starving, and they can see the full stores of the %s from their hill." % [hungry["name"], neighbor["name"]],
			"tribe": hungry["name"],
			"choices": [
				{"label": "Turn their eyes to the hunt", "hint": "The forest is dangerous in lean times.",
					"effects": [{"type": "food", "tribe": hungry["name"], "amount": 2}, {"type": "population", "tribe": hungry["name"], "amount": -8}]},
				{"label": "Let them raid the %s" % neighbor["name"], "hint": "Food taken is food someone else lacks.",
					"effects": [{"type": "food", "tribe": hungry["name"], "amount": 3}, {"type": "food", "tribe": neighbor["name"], "amount": -3}, {"type": "kindness", "tribe": "", "amount": -1}]},
				{"label": "Do nothing", "hint": "The weak will not all survive the winter.",
					"effects": [{"type": "population", "tribe": hungry["name"], "amount": -12}]},
			],
		}
	if int(largest["population"]) >= 50:
		return {
			"title": "The Restless Young",
			"situation": "The young of the %s say the old fire is too crowded. They want to cross the hills and start their own." % largest["name"],
			"tribe": largest["name"],
			"choices": [
				{"label": "Bless their journey", "hint": "A new tribe will be born. The %s will be smaller." % largest["name"],
					"effects": [{"type": "split", "tribe": largest["name"], "amount": 0}, {"type": "kindness", "tribe": "", "amount": 1}]},
				{"label": "Keep the tribe together", "hint": "Crowded fires burn through their food.",
					"effects": [{"type": "food", "tribe": largest["name"], "amount": -2}, {"type": "influence", "tribe": "", "amount": 1}]},
			],
		}
	var tribe: Dictionary = tribes[rng.randi_range(0, tribes.size() - 1)]
	return {
		"title": "A Strange Seed",
		"situation": "A child of the %s found a seed that grows fast, but its fruit makes some people sick." % tribe["name"],
		"tribe": tribe["name"],
		"choices": [
			{"label": "Let them plant it", "hint": "More food, and some will fall ill.",
				"effects": [{"type": "food", "tribe": tribe["name"], "amount": 3}, {"type": "population", "tribe": tribe["name"], "amount": -5}]},
			{"label": "Make them burn it", "hint": "Safe, but they will wonder why the god forbids gifts.",
				"effects": [{"type": "influence", "tribe": "", "amount": 1}, {"type": "kindness", "tribe": "", "amount": -1}]},
		],
	}
