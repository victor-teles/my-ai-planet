class_name Miracles
extends RefCounted
## What the player god can do. Every miracle costs Influence, is logged as an event (so the
## Oracle can cite it), and shifts the player's kindness and disposition, which set the world's tone.

const DEFINITIONS := {
	"rain": {"name": "Rain", "cost": 3.0, "kindness": 1, "needs_tribe": false,
		"description": "Ends any drought and blesses the valley with rain for a year."},
	"harvest": {"name": "Harvest", "cost": 2.0, "kindness": 1, "needs_tribe": true,
		"description": "Fills a tribe's stores with four months of food."},
	"drought": {"name": "Drought", "cost": 2.0, "kindness": -1, "needs_tribe": false,
		"description": "Holds back the rain for a year."},
	"plague": {"name": "Plague", "cost": 3.0, "kindness": -2, "needs_tribe": true,
		"description": "A sickness sweeps through a tribe. The frail die first; the hardy pass on their blood."},
	"muse": {"name": "Muse", "cost": 3.0, "kindness": 0, "needs_tribe": true,
		"description": "Whisper an idea to the cleverest of a tribe: they discover something new."},
	"smite": {"name": "Smite", "cost": 4.0, "kindness": -2, "needs_tribe": true,
		"description": "Strike down a tribe's ruler with lightning. Who takes the seat next is up to them, and they will fear you."},
	"awaken": {"name": "Awaken", "cost": 3.0, "kindness": 1, "needs_tribe": true,
		"description": "Open the people's eyes: they see their rulers plainly. Legitimacy and loyalty fall; the unhappy may rise."},
	"sanctify": {"name": "Sanctify", "cost": 3.0, "kindness": 0, "needs_tribe": true,
		"description": "Bless a tribe's ruler before everyone: their rule seems the will of heaven, whatever it is."},
}
const ORDER: Array[String] = ["rain", "harvest", "drought", "plague", "muse", "smite", "awaken", "sanctify"]
const HARVEST_DAYS := 120.0
const PLAGUE_DEATH := 0.1 ## chance to die for the hardiest; the frailest face PLAGUE_DEATH + PLAGUE_FRAILTY
const PLAGUE_FRAILTY := 0.35


## Empty string if the miracle can be cast, otherwise the reason it can't.
static func why_not(state: WorldState, id: String, tribe_name: String = "") -> String:
	if not DEFINITIONS.has(id):
		return "Unknown miracle"
	var definition: Dictionary = DEFINITIONS[id]
	if state.influence < float(definition["cost"]):
		return "Not enough Influence"
	if definition["needs_tribe"] and state.tribe_index(tribe_name) == -1:
		return "Choose a tribe first"
	if id == "drought" and state.drought_months_left > 0:
		return "There is already a drought"
	if id == "muse" and Knowledge.discoverable(state.tribe_knowledge[state.tribe_index(tribe_name)]).is_empty():
		return "They already know everything this era can teach"
	if id in ["smite", "sanctify"] and state.chief_of(tribe_name) == -1:
		return "They have no ruler right now"
	return ""


## Applies the miracle between ticks. Returns false (changing nothing) if it can't be cast.
static func cast(state: WorldState, id: String, tribe_name: String = "") -> bool:
	if not why_not(state, id, tribe_name).is_empty():
		return false
	var definition: Dictionary = DEFINITIONS[id]
	var tribe := state.tribe_index(tribe_name)
	var data := {"miracle": id}
	match id:
		"rain":
			state.drought_months_left = 0
			state.blessed_rain_months = WorldState.MONTHS_PER_YEAR
		"harvest":
			state.tribe_food[tribe] += state.tribe_population[tribe] * HARVEST_DAYS
			data["tribe"] = tribe_name
		"drought":
			state.drought_months_left = WorldState.MONTHS_PER_YEAR
			state.blessed_rain_months = 0
		"plague":
			data["tribe"] = tribe_name
			data["deaths"] = _plague(state, tribe_name)
		"smite":
			var ruler := state.chief_of(tribe_name)
			data["tribe"] = tribe_name
			data["id"] = state.person_ids[ruler]
			data["name"] = state.person_names[ruler]
			state.log_event("miracle", data)
			state.tribe_fear[tribe] = mini(state.tribe_fear[tribe] + 20, 100)
			state.kill_person(ruler, "lightning")
			_pay(state, definition)
			state.settle()
			return true
		"awaken":
			data["tribe"] = tribe_name
			state.tribe_legitimacy[tribe] = maxi(state.tribe_legitimacy[tribe] - 25, 0)
			state.tribe_unrest[tribe] = mini(state.tribe_unrest[tribe] + 15, 100)
			for p: int in state.people_of(tribe_name):
				if People.is_adult(state, p) and state.person_ids[p] != state.tribe_chiefs[tribe]:
					state.person_loyalty[p] = maxi(state.person_loyalty[p] - 20, 0)
		"sanctify":
			var ruler := state.chief_of(tribe_name)
			data["tribe"] = tribe_name
			data["id"] = state.person_ids[ruler]
			data["name"] = state.person_names[ruler]
			state.tribe_legitimacy[tribe] = mini(state.tribe_legitimacy[tribe] + 30, 100)
			var powers: Dictionary = state.tribe_power[tribe]
			powers["ruler"] = mini(int(powers.get("ruler", 0)) + 15, 100)
			state.tribe_culture[tribe]["piety"] = clampi(int(state.tribe_culture[tribe].get("piety", 0)) + 10, -100, 100)
			state.life(state.person_ids[ruler], "Was blessed by the god before all the %s." % tribe_name, "chief")
		"muse":
			var genius := _cleverest(state, tribe_name)
			var open := Knowledge.discoverable(state.tribe_knowledge[tribe])
			data["tribe"] = tribe_name
			data["id"] = state.person_ids[genius]
			data["name"] = state.person_names[genius]
			state.log_event("miracle", data)
			WorkSystem.discover(state, tribe, genius, open[state.rng.pick_index(open.size())])
			_pay(state, definition)
			state.settle()
			return true
	_pay(state, definition)
	state.log_event("miracle", data)
	state.settle()
	return true


## The god spends the Influence, and the people (and the disposition) remember the deed.
static func _pay(state: WorldState, definition: Dictionary) -> void:
	state.influence -= float(definition["cost"])
	state.kindness += int(definition["kindness"])
	state.record_intervention(int(definition["kindness"]))


## Everyone in the tribe falls sick; each dies with a chance that grows with frailty. Returns the dead.
static func _plague(state: WorldState, tribe_name: String) -> int:
	var deaths := 0
	var ids: Array[int] = []
	for p: int in state.people_of(tribe_name):
		ids.append(state.person_ids[p])
	for id: int in ids:
		var p := state.index_of(id)
		var weakness := 1.0 - Genetics.express(state.person_genomes[p], "vitality")
		if Genetics.is_frail(state.person_genomes[p]):
			weakness = 1.0
		if state.rng.chance(PLAGUE_DEATH + PLAGUE_FRAILTY * weakness):
			state.kill_person(p, "plague")
			deaths += 1
		else:
			state.person_sick[p] = maxi(state.person_sick[p], state.rng.randi_range(15, 40))
			state.life(id, "Survived the plague.", "health")
	return deaths


static func _cleverest(state: WorldState, tribe_name: String) -> int:
	var best := -1
	for p: int in state.people_of(tribe_name):
		if People.is_adult(state, p) and (best == -1 or Genetics.express(state.person_genomes[p], "intellect") > Genetics.express(state.person_genomes[best], "intellect")):
			best = p
	return best if best != -1 else state.people_of(tribe_name)[0]
