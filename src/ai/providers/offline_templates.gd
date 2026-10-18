class_name OfflineTemplatesProvider
extends AIProvider
## Always-available fallback that answers from hand-written templates.
## Deterministic for a given request.seed_value, and never touches the sim's RNG.


func get_id() -> String:
	return "offline"


func is_available() -> bool:
	return true


func is_free() -> bool:
	return true


func complete(request: AIRequest) -> AIResponse:
	match request.task:
		"prophecy":
			return AIResponse.success(get_id(), _prophecy(request))
		"chronicle":
			return AIResponse.success(get_id(), _chronicle(request))
		"dilemma":
			return AIResponse.success(get_id(), _dilemma(request))
		"destiny":
			return AIResponse.success(get_id(), _destiny(request))
		"thought":
			return AIResponse.success(get_id(), {"thought": thought(request)})
	return AIResponse.failure(get_id(), "Offline templates don't cover task '%s'" % request.task)


func _prophecy(request: AIRequest) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = request.seed_value
	var world := request.context
	var tribes: Array = world.get("tribes", [])
	var population := int(world.get("total_population", 0))
	var first_tribe := String(tribes[0]["name"]) if not tribes.is_empty() else "the people"
	var largest: Dictionary = tribes[0] if not tribes.is_empty() else {"name": first_tribe, "population": population}
	var buildings := 0
	var known := {}
	for tribe: Dictionary in tribes:
		if int(tribe["population"]) > int(largest["population"]):
			largest = tribe
		for type: String in tribe.get("buildings", {}):
			buildings += int(tribe["buildings"][type])
		for tech: String in tribe.get("knows", []):
			if tech not in Knowledge.STARTING:
				known[tech] = true
	var discoveries := known.size()
	# Each template aims at an outcome that is roughly a coin toss without the god's help.
	if world.get("in_drought", false) and population >= 10:
		var survivors := maxi(int(population * 0.9), 1)
		return {
			"text": "The sky is closing its hand. Within %d years, fewer than %d souls will be left in the valley." % [10, survivors],
			"metric": "total_population", "op": "<=", "value": survivors, "years_from_now": 10,
		}
	var options: Array[Dictionary] = []
	if discoveries < Knowledge.ORDER.size() - Knowledge.STARTING.size():
		var target := mini(discoveries + 2, Knowledge.ORDER.size() - Knowledge.STARTING.size())
		options.append({
			"text": "Clever hands will wake. Before %d winters pass, the valley will know %d secrets it does not know today." % [10, target - discoveries],
			"metric": "discoveries", "op": ">=", "value": target, "years_from_now": 10,
		})
	var more := buildings + maxi(5, population / 4)
	options.append({
		"text": "I see roofs rising where there is grass. Within %d years, %d buildings will stand in the valley." % [10, more],
		"metric": "building_count", "op": ">=", "value": more, "years_from_now": 10,
	})
	_society_prophecies(tribes, options)
	var grown := int(population * 1.3) + 4
	options.append({
		"text": "The cradles will not be empty. In %d years, %d people will walk the valley." % [15, grown],
		"metric": "total_population", "op": ">=", "value": grown, "years_from_now": 15,
	})
	if int(largest["population"]) >= 45:
		options.append({
			"text": "The fire of the %s grows too crowded. Before %d years pass, %d fires will burn in the valley." % [largest["name"], 15, tribes.size() + 1],
			"metric": "tribe_count", "op": ">=", "value": tribes.size() + 1, "years_from_now": 15,
		})
	if tribes.size() > 1:
		var size := int(int(largest["population"]) * 1.3) + 1
		options.append({
			"text": "The %s will grow mighty. Before %d years pass, %d of them will sit around one fire." % [largest["name"], 20, size],
			"metric": "largest_tribe_population", "op": ">=", "value": size, "years_from_now": 20,
		})
	return options[rng.randi_range(0, options.size() - 1)]


## Prophecies about how the tribes are ruled: a new age, a tyranny, the rich and the poor, a vassal.
func _society_prophecies(tribes: Array, options: Array[Dictionary]) -> void:
	var highest := 0
	var darkest: Dictionary = {}
	var widest: Dictionary = {}
	var vassals := 0
	for tribe: Dictionary in tribes:
		var society: Dictionary = tribe.get("society", {})
		highest = maxi(highest, int(society.get("age_level", 0)))
		if darkest.is_empty() or int(society.get("dystopia", 0)) > int(darkest["society"].get("dystopia", 0)):
			darkest = tribe
		if widest.is_empty() or int(society.get("inequality", 0)) > int(widest["society"].get("inequality", 0)):
			widest = tribe
		if society.has("vassal_of"):
			vassals += 1
	if highest < Knowledge.AGES.size() - 1:
		var next := Knowledge.age_name(highest + 1)
		options.append({
			"text": "Something new is stirring in the forges and the scribes' huts. Within %d years, the island will enter the %s." % [30, next],
			"metric": "highest_age", "op": ">=", "value": highest + 1, "years_from_now": 30,
		})
	if not darkest.is_empty():
		var dark := int(darkest["society"].get("dystopia", 0))
		if dark >= 20 and dark <= 75:
			options.append({
				"text": "I see eyes in the walls of the %s, and chains where there were none. Before %d years pass, their rulers' grip will close." % [darkest["name"], 20],
				"metric": "max_dystopia", "op": ">=", "value": dark + 20, "years_from_now": 20,
			})
	if not widest.is_empty() and int(widest["society"].get("inequality", 0)) >= 30 and int(widest["society"].get("inequality", 0)) <= 70:
		var gap := int(widest["society"]["inequality"])
		options.append({
			"text": "The granaries of the few are filling, and the bowls of the many are not. Within %d years, the %s will be split into the rich and the poor." % [20, widest["name"]],
			"metric": "max_inequality", "op": ">=", "value": gap + 15, "years_from_now": 20,
		})
	if vassals == 0 and tribes.size() >= 2 and highest >= 1:
		options.append({
			"text": "A crown is being hammered in bronze. Before %d years pass, one tribe will kneel and pay tribute to another." % 25,
			"metric": "vassal_count", "op": ">=", "value": 1, "years_from_now": 25,
		})


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
	if not miracles.is_empty():
		causes.append("the god sent %s" % ", ".join(miracles))
	if counts.has("drought_started"):
		causes.append("%d drought%s dried the valley" % [counts["drought_started"], "s" if counts["drought_started"] > 1 else ""])
	if counts.has("famine"):
		causes.append("hunger struck %d time%s" % [counts["famine"], "s" if counts["famine"] > 1 else ""])
	if counts.has("tribe_split"):
		causes.append("%d new tribe%s broke away" % [counts["tribe_split"], "s" if counts["tribe_split"] > 1 else ""])
	if counts.has("war"):
		causes.append("the tribes went to war %d time%s" % [counts["war"], "s" if counts["war"] > 1 else ""])
	if counts.has("tribes_merged"):
		causes.append("%d tribe%s joined a friend's fire" % [counts["tribes_merged"], "s" if counts["tribes_merged"] > 1 else ""])
	if counts.has("water_low"):
		causes.append("the springs ran low %d time%s" % [counts["water_low"], "s" if counts["water_low"] > 1 else ""])
	if counts.has("discovery"):
		causes.append("%d discover%s changed how the people lived" % [counts["discovery"], "ies" if counts["discovery"] > 1 else "y"])
	if counts.has("epidemic"):
		causes.append("fever swept the camps %d time%s" % [counts["epidemic"], "s" if counts["epidemic"] > 1 else ""])
	if counts.has("revolution"):
		causes.append("the people rose and overthrew their rulers")
	if counts.has("coup"):
		causes.append("the warriors seized power")
	if counts.has("uprising_crushed"):
		causes.append("an uprising was crushed")
	if counts.has("crackdown"):
		causes.append("the guards broke up the crowds %d time%s" % [counts["crackdown"], "s" if counts["crackdown"] > 1 else ""])
	if counts.has("new_age"):
		causes.append("the island entered a new age")
	if counts.has("vassal"):
		causes.append("%d tribe%s bowed to an overlord" % [counts["vassal"], "s" if counts["vassal"] > 1 else ""])
	if counts.has("law_passed"):
		causes.append("%d new law%s bound the people" % [counts["law_passed"], "s" if counts["law_passed"] > 1 else ""])
	if counts.has("building_done"):
		causes.append("%d building%s rose around the fires" % [counts["building_done"], "s" if counts["building_done"] > 1 else ""])
	if causes.is_empty():
		causes.append("the years passed quietly")

	var opening := "As the Oracle foretold, it came to pass." if came_true else "The Oracle spoke, but the world refused the prophecy."
	var middle := "In those years, %s." % "; ".join(causes.slice(0, 3))
	var daily: Dictionary = record.get("daily_life", {})
	var life := PackedStringArray()
	if int(daily.get("birth", 0)) > 0:
		life.append("%d %s born" % [int(daily["birth"]), "child was" if int(daily["birth"]) == 1 else "children were"])
	if int(daily.get("death", 0)) > 0:
		life.append("%d %s buried" % [int(daily["death"]), "was" if int(daily["death"]) == 1 else "were"])
	if int(daily.get("marriage", 0)) > 0:
		life.append("%d %s married" % [int(daily["marriage"]), "couple" if int(daily["marriage"]) == 1 else "couples"])
	var joined := ", ".join(life)
	var days := "" if life.is_empty() else " " + joined.left(1).to_upper() + joined.substr(1) + "."
	var ending := "Now %d people live in %d tribes." % [int(record.get("population_now", 0)), int(record.get("tribes_now", 0))]
	return {
		"title": "The Prophecy Fulfilled" if came_true else "The Prophecy Broken",
		"text": "%s %s%s %s" % [opening, middle, days, ending],
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
	var shared := _failing_shared_water(world)
	if not shared.is_empty():
		var first: String = shared["tribes"][0]
		var second: String = shared["tribes"][1]
		return {
			"title": "The Sinking Spring",
			"situation": "%s is falling, and both the %s and the %s fill their jars there. Each says the other drinks too much." % [String(shared["water"]).capitalize(), first, second],
			"tribe": first,
			"choices": [
				{"label": "Send the %s to find new water" % first, "hint": "The journey is hard, but the quarrel will cool.",
					"effects": [{"type": "food", "tribe": first, "amount": -2}, {"type": "relation", "tribe": second, "amount": 15}]},
				{"label": "Let them fight over it", "hint": "The stronger will drink. The weaker will remember.",
					"effects": [{"type": "relation", "tribe": second, "amount": -30}, {"type": "kindness", "tribe": "", "amount": -1}]},
				{"label": "Fill the spring yourself", "hint": "Rain for everyone, at a price.",
					"effects": [{"type": "rain", "tribe": "", "amount": 6}, {"type": "influence", "tribe": "", "amount": -3}]},
			],
		}
	var rivals := _worst_relation(world)
	if not rivals.is_empty() and int(rivals["relation"]) <= -25:
		var first: String = rivals["tribes"][0]
		var second: String = rivals["tribes"][1]
		return {
			"title": "Spears at the Border",
			"situation": "The %s and the %s glare at each other across the hills. A hunter was hurt, and each tribe blames the other." % [first, second],
			"tribe": first,
			"choices": [
				{"label": "Bring them to one fire", "hint": "Peace costs pride, and some food for the feast.",
					"effects": [{"type": "relation", "tribe": second, "amount": 30}, {"type": "food", "tribe": first, "amount": -1}, {"type": "food", "tribe": second, "amount": -1}]},
				{"label": "Bless the %s's spears" % first, "hint": "A war may come, and the %s may win it." % first,
					"effects": [{"type": "relation", "tribe": second, "amount": -25}, {"type": "population", "tribe": first, "amount": 5}, {"type": "kindness", "tribe": "", "amount": -1}]},
				{"label": "Stay silent", "hint": "Old grudges grow in silence.",
					"effects": [{"type": "relation", "tribe": second, "amount": -10}]},
			],
		}
	var political := _political_dilemma(tribes)
	if not political.is_empty():
		return political
	if float(hungry["food_months"]) < 1.5 and tribes.size() > 1:
		var neighbor: Dictionary = largest if largest != hungry else tribes[(tribes.find(hungry) + 1) % tribes.size()]
		return {
			"title": "Empty Bellies",
			"situation": "The %s are starving, and they can see the full stores of the %s from their hill." % [hungry["name"], neighbor["name"]],
			"tribe": hungry["name"],
			"choices": [
				{"label": "Turn their eyes to the hunt", "hint": "The forest is dangerous in lean times.",
					"effects": [{"type": "food", "tribe": hungry["name"], "amount": 2}, {"type": "population", "tribe": hungry["name"], "amount": -8}]},
				{"label": "Let them raid the %s" % neighbor["name"], "hint": "Food taken is food someone else lacks, and they will not forget.",
					"effects": [{"type": "food", "tribe": hungry["name"], "amount": 3}, {"type": "food", "tribe": neighbor["name"], "amount": -3}, {"type": "relation", "tribe": neighbor["name"], "amount": -25}]},
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


## Cards about how a tribe is ruled: a crowd at the gate, a ruler who wants more power, a tribe
## under watch, the hoards of the rich.
func _political_dilemma(tribes: Array) -> Dictionary:
	for tribe: Dictionary in tribes:
		var society: Dictionary = tribe.get("society", {})
		var name := String(tribe["name"])
		var laws: Array = society.get("laws", [])
		var age := int(society.get("age_level", 0))
		var ruler := String((tribe.get("chief", {}) as Dictionary).get("name", "their ruler"))
		if String(society.get("crisis", "")).begins_with("protests"):
			return {
				"title": "The Crowd at the Gate",
				"situation": "The %s fill the square and shout at %s's door. The guards wait for an order, and so does the sky." % [name, ruler],
				"tribe": name,
				"choices": [
					{"label": "Stand with the crowd", "hint": "The rulers will look small. Crowds that win once come back.",
						"effects": [{"type": "legitimacy", "tribe": name, "amount": -20}, {"type": "unrest", "tribe": name, "amount": 10}, {"type": "kindness", "tribe": "", "amount": 1}]},
					{"label": "Stand with %s" % ruler, "hint": "Order will hold, and fear with it.",
						"effects": [{"type": "legitimacy", "tribe": name, "amount": 15}, {"type": "unrest", "tribe": name, "amount": -20}, {"type": "kindness", "tribe": "", "amount": -1}]},
					{"label": "Let them settle it", "hint": "Whatever happens, it will be theirs.",
						"effects": [{"type": "influence", "tribe": "", "amount": 1}]},
				],
			}
		if age >= 1 and int(society.get("unrest", 0)) >= 35 and "emergency_powers" not in laws:
			return {
				"title": "Powers for the Hard Times",
				"situation": "%s says the %s are restless and ungovernable, and asks the sky to bless the right to rule by decree until calm returns." % [ruler, name],
				"tribe": name,
				"choices": [
					{"label": "Grant the powers", "hint": "Calm, for now. Such powers are seldom given back.",
						"effects": [{"type": "law", "tribe": name, "amount": 1, "law": "emergency_powers"}, {"type": "unrest", "tribe": name, "amount": -15}]},
					{"label": "Refuse", "hint": "The ruler will be weaker, and the restless bolder.",
						"effects": [{"type": "legitimacy", "tribe": name, "amount": -10}, {"type": "unrest", "tribe": name, "amount": 10}, {"type": "kindness", "tribe": "", "amount": 1}]},
				],
			}
		var watched := "surveillance_net" in laws or "secret_police" in laws
		if watched and int(society.get("dystopia", 0)) >= 45:
			var law := "surveillance_net" if "surveillance_net" in laws else "secret_police"
			return {
				"title": "Eyes Everywhere",
				"situation": "Among the %s nobody speaks freely anymore; someone is always listening. Those who prayed to the sky now pray quietly." % name,
				"tribe": name,
				"choices": [
					{"label": "Blind the watchers", "hint": "The eyes will close. The rulers will feel naked, and afraid.",
						"effects": [{"type": "law", "tribe": name, "amount": -1, "law": law}, {"type": "legitimacy", "tribe": name, "amount": -15}, {"type": "influence", "tribe": "", "amount": -2}]},
					{"label": "Let them watch", "hint": "It is quiet. Quiet is not peace.",
						"effects": [{"type": "unrest", "tribe": name, "amount": -10}, {"type": "kindness", "tribe": "", "amount": -1}]},
				],
			}
		if int(society.get("inequality", 0)) >= 50:
			var share := "universal_dividend" if age >= 4 else ("labor_rights" if age >= 3 else "shared_stores")
			return {
				"title": "The Hoards of the Few",
				"situation": "A handful of families of the %s own most of what there is. The rest work their fields and their machines, and wonder why." % name,
				"tribe": name,
				"choices": [
					{"label": "Make them share", "hint": "The poor will bless you. The rich have long memories.",
						"effects": [{"type": "law", "tribe": name, "amount": 1, "law": share}, {"type": "legitimacy", "tribe": name, "amount": -5}, {"type": "kindness", "tribe": "", "amount": 1}]},
					{"label": "Bless the rich", "hint": "Wealth will build. Resentment will too.",
						"effects": [{"type": "legitimacy", "tribe": name, "amount": 5}, {"type": "unrest", "tribe": name, "amount": 10}]},
				],
			}
	return {}


## The island's last chapter, from the destiny's meaning and the turns of history that led there.
func _destiny(request: AIRequest) -> Dictionary:
	var record := request.context
	var destiny: Dictionary = record.get("destiny", {})
	var realm: Dictionary = record.get("realm", {})
	var society: Dictionary = realm.get("society", {})
	var counts: Dictionary = record.get("history_counts", {})
	var tribe := String(realm.get("tribe", "the people"))
	var causes := PackedStringArray()
	var laws: Array = society.get("laws", [])
	var dark: Array[String] = []
	for law: Variant in laws:
		if Laws.is_dystopian(String(law)):
			dark.append(Laws.name_of(String(law)).to_lower())
	if not dark.is_empty():
		causes.append("the %s lived under %s" % [tribe, ", ".join(dark.slice(0, 3))])
	for type: String in ["revolution", "coup", "uprising_crushed", "capture", "crackdown", "schism", "vassal"]:
		if counts.has(type):
			causes.append("%s: %d" % [{"revolution": "revolutions", "coup": "coups", "uprising_crushed": "uprisings crushed", "capture": "the state bought", "crackdown": "crackdowns", "schism": "schisms", "vassal": "tribes made vassals"}[type], int(counts[type])])
	if counts.has("miracle"):
		causes.append("the god worked %d miracles" % int(counts["miracle"]))
	if causes.is_empty():
		causes.append("the ages passed one after another")
	var text := "%s %s In the end the %s became a %s, and the island became %s." % [
		String(destiny.get("meaning", "")),
		"It was the work of centuries: %s." % "; ".join(causes.slice(0, 3)),
		tribe, String(society.get("government", "realm")).to_lower(), String(destiny.get("name", "what it is")),
	]
	return {"title": String(destiny.get("name", "The Last Chapter")), "text": text, "causes": Array(causes.slice(0, 3))}


## A water source under a third full that two or more tribes drink from: {"water", "tribes"}.
func _failing_shared_water(world: Dictionary) -> Dictionary:
	for water: Dictionary in world.get("water_sources", []):
		if float(water["fullness"]) >= 0.35:
			continue
		var drinkers := PackedStringArray()
		for tribe: Dictionary in world.get("tribes", []):
			if tribe["drinks_from"] == water["name"]:
				drinkers.append(String(tribe["name"]))
		if drinkers.size() >= 2:
			return {"water": water["name"], "tribes": drinkers}
	return {}


func _worst_relation(world: Dictionary) -> Dictionary:
	var worst := {}
	for bond: Dictionary in world.get("relations", []):
		if worst.is_empty() or int(bond["relation"]) < int(worst["relation"]):
			worst = bond
	return worst


const TRAIT_LINES := {
	"brave": ["Let them come. I am not afraid.", "Someone has to go first. It may as well be me."],
	"fierce": ["If anyone crosses the stream again, we fight.", "Soft hands make hungry children."],
	"kind": ["We should share what we have.", "Even a stranger is welcome at our fire."],
	"cheerful": ["Still, the fire is warm tonight.", "Someone sang this morning, and everyone joined in."],
	"wise": ["Patience. Hard years pass, like the others did.", "Store a little more than you think you need."],
	"proud": ["The %s bow to no one.", "Our fire burned here before any other."],
	"curious": ["I wonder what lies past the far hills.", "The clouds below the island must end somewhere."],
	"devout": ["I will leave an offering for the sky tonight.", "The sky is watching. I can feel it."],
	"greedy": ["I keep a little extra hidden. Just in case.", "Why should the others eat what we gathered?"],
	"lazy": ["Tomorrow, maybe.", "The berries will still be there after a nap."],
}


## A first-person thought from a person description (see People.describe): their own life first,
## then the tribe, then a line in the voice of one of their traits.
func thought(request: AIRequest) -> String:
	var who := request.context
	var rng := RandomNumberGenerator.new()
	rng.seed = request.seed_value
	var stage := String(who.get("stage", "adult"))
	if stage in ["infant", "child"]:
		return _child_thought(who, rng)
	var concern := _personal_concern(who, rng)
	if concern.is_empty():
		concern = _tribe_concern(who, rng)
	if who.get("is_chief", false) and concern:
		concern = "As chief, I carry this: " + concern.left(1).to_lower() + concern.substr(1)
	var traits: Array = who.get("traits", [])
	var trait_id := String(traits[rng.randi_range(0, traits.size() - 1)]) if not traits.is_empty() else ""
	var lines: Array = TRAIT_LINES.get(trait_id, ["Another day in the valley."])
	var line := String(lines[rng.randi_range(0, lines.size() - 1)])
	if line.contains("%s"):
		line = line % who.get("tribe", "people")
	return ("%s %s" % [concern, line]).strip_edges()


func _child_thought(who: Dictionary, rng: RandomNumberGenerator) -> String:
	var family: Dictionary = who.get("family", {})
	var lines: Array[String] = ["When I grow up I will be the best %s of the %s." % [["hunter", "healer", "builder", "fisher"][rng.randi_range(0, 3)], who.get("tribe", "tribe")]]
	if String(who.get("doing", "")) == "sick":
		lines = ["My head is hot and everything hurts. I want to go out and play."]
	for parent: String in ["mother", "father"]:
		var entry := String(family.get(parent, ""))
		if entry.ends_with("(dead)"):
			lines.append("I miss my %s. Everyone says %s." % [parent, "she is with the sky now" if parent == "mother" else "he is with the sky now"])
	var friends: Array = who.get("friends", [])
	if not friends.is_empty():
		lines.append("%s and I found a secret place by the water today." % friends[0])
	return lines[rng.randi_range(0, lines.size() - 1)]


## Something from their own life: sickness, grief, a baby coming, love, a rival, their work.
func _personal_concern(who: Dictionary, rng: RandomNumberGenerator) -> String:
	var family: Dictionary = who.get("family", {})
	var doing := String(who.get("doing", ""))
	if doing == "sick" or int(who.get("health", 100)) < 35:
		return "I can barely stand. If the fever doesn't break soon..." if int(who.get("health", 100)) < 35 else "This fever won't let me work. I hate lying here while the others toil."
	if doing == "mourning":
		for key: String in ["mother", "father"]:
			if String(family.get(key, "")).ends_with("(dead)"):
				return "I still look for my %s by the fire, %s." % [key, String(family[key]).get_slice(" (", 0)]
		return "The hearth feels empty now. Grief sits with me every evening."
	if who.get("pregnant", false):
		var partner := String(family.get("husband", family.get("wife", "")))
		return "The baby kicks at night. %s" % ("%s already talks about names." % partner if partner else "I wonder who it will look like.")
	var options: Array[String] = []
	for key: String in ["wife", "husband"]:
		if family.has(key):
			options.append("%s laughed at me this morning, and I didn't mind at all." % family[key])
	if family.has("children"):
		var children := String(family["children"])
		options.append("My children are growing so fast." if not children.contains("lost") else "I have buried a child. Every new morning I count the others.")
	var rivals: Array = who.get("rivals", [])
	if not rivals.is_empty():
		options.append("%s has been talking about me again. One day we will settle this." % rivals[0])
	var friends: Array = who.get("friends", [])
	if not friends.is_empty():
		options.append("%s makes the long days easier." % friends[0])
	var role := String(who.get("role", ""))
	if role and role not in ["without work", "youth"]:
		options.append("A good %s never rests long. There is always more to do." % role if not role.begins_with("apprentice") else "I'm learning to be a %s. My hands are clumsy, but getting better." % role.trim_prefix("apprentice "))
	if options.is_empty():
		return ""
	return options[rng.randi_range(0, options.size() - 1)]


func _tribe_concern(who: Dictionary, rng: RandomNumberGenerator) -> String:
	var needs: Dictionary = who.get("needs", {})
	var worst := ""
	for need: String in needs:
		if worst.is_empty() or float(needs[need]) < float(needs[worst]):
			worst = need
	var rival := ""
	var friend := ""
	for neighbor: Dictionary in who.get("neighbors", []):
		if rival.is_empty() and int(neighbor["relation"]) <= -25:
			rival = neighbor["tribe"]
		if friend.is_empty() and int(neighbor["relation"]) >= 25:
			friend = neighbor["tribe"]
	if worst and float(needs[worst]) < 0.5:
		match worst:
			"food":
				return "The stores are nearly bare, and the little ones keep asking for more."
			"water":
				return "%s is so low we drink mud. Someone must find new water." % String(who.get("drinks_from", "The spring")).capitalize()
			"shelter":
				return "Too many of us under too few roofs. We need to build."
			"safety":
				return "I don't sleep well. The %s watch us from the hills." % rival if rival else "I don't sleep well these nights."
	if rival:
		return "The %s cannot be trusted." % rival
	if friend and rng.randf() < 0.5:
		return "Our cousins the %s are good people." % friend
	if int(who.get("god_kindness", 0)) <= -3:
		return "The sky is angry with us. What did we do?"
	if int(who.get("god_kindness", 0)) >= 3:
		return "The sky has been good to us."
	return ""
