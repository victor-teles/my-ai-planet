class_name People
extends RefCounted
## Questions about people: their age and stage of life, their family, their personality and
## what a chief's personality does to the tribe. Also founds the first band.
## Everything here reads WorldState; the systems decide what happens.

const INFANT_UNTIL := 3 ## years
const CHILD_UNTIL := 12 ## then apprentices learn a parent's work
const ADULT_AT := 16
const ELDER_AT := 55
const RETIRE_AT := 64 ## no more work; elders teach the young instead

## What a trait does when its owner leads the tribe. Missing keys mean no effect.
##   relation: added to the tribe's relation with every other tribe each year
##   war: strength in war (multiplier)    gather: food gathered (multiplier)
##   starve: health lost in hungry months (multiplier)    split: chance the young leave (multiplier)
##   faith: Influence the god earns per year
const TRAITS := {
	"brave": {"war": 1.25, "description": "Fights hard: the tribe is stronger in war."},
	"fierce": {"relation": -2, "war": 1.15, "description": "Quick to anger: neighbors cool toward the tribe."},
	"kind": {"relation": 2, "description": "Welcomes strangers: neighbors warm to the tribe."},
	"cheerful": {"relation": 1, "description": "Laughs easily: neighbors like the tribe a little more."},
	"wise": {"starve": 0.6, "description": "Rations well: hunger hurts less."},
	"proud": {"relation": -1, "split": 0.5, "description": "Holds the tribe together, but looks down on others."},
	"curious": {"split": 1.6, "description": "Dreams of the far hills: the young leave sooner."},
	"devout": {"faith": 0.04, "description": "Prays often: the god gains more Influence."},
	"greedy": {"gather": 1.06, "relation": -1, "description": "Hoards: more food, fewer friends."},
	"lazy": {"gather": 0.93, "description": "Rests often: the tribe gathers less."},
}
const TRAIT_ORDER: Array[String] = ["brave", "fierce", "kind", "cheerful", "wise", "proud", "curious", "devout", "greedy", "lazy"]
const FOUNDING_COUPLES := 5


# --- Age and stage ------------------------------------------------------------------

static func age(state: WorldState, p: int) -> int:
	return WorldState.year_of(state.tick - state.person_born[p])


static func age_days(state: WorldState, p: int) -> int:
	return state.tick - state.person_born[p]


## "infant", "child", "youth" (an apprentice), "adult" or "elder".
static func stage(state: WorldState, p: int) -> String:
	return stage_at(age(state, p))


static func stage_at(years: int) -> String:
	if years < INFANT_UNTIL:
		return "infant"
	if years < CHILD_UNTIL:
		return "child"
	if years < ADULT_AT:
		return "youth"
	if years < ELDER_AT:
		return "adult"
	return "elder"


static func is_adult(state: WorldState, p: int) -> bool:
	return age(state, p) >= ADULT_AT


static func is_female(state: WorldState, p: int) -> bool:
	return state.person_sexes[p] == "f"


## How many of each stage live in a tribe.
static func stage_counts(state: WorldState, tribe: String) -> Dictionary:
	var counts := {}
	for p: int in state.person_ids.size():
		if state.person_tribes[p] == tribe:
			var s := stage(state, p)
			counts[s] = int(counts.get(s, 0)) + 1
	return counts


# --- Names and family ---------------------------------------------------------------

static func full_name(state: WorldState, p: int) -> String:
	return "%s %s" % [state.person_names[p], state.person_families[p]]


## The name of anyone, living or remembered; "" if forgotten.
static func name_of(state: WorldState, id: int) -> String:
	var p := state.index_of(id)
	if p != -1:
		return state.person_names[p]
	var record: Dictionary = state.dead.get(str(id), {})
	return String(record.get("name", ""))


static func generation_of(state: WorldState, id: int) -> int:
	if id < 0:
		return 0
	var p := state.index_of(id)
	if p != -1:
		return state.person_generations[p]
	return int((state.dead.get(str(id), {}) as Dictionary).get("generation", 0))


static func max_generation(state: WorldState) -> int:
	var most := 0
	for generation: int in state.person_generations:
		most = maxi(most, generation)
	return most


## [mother id, father id] of anyone living or remembered; -1 where unknown.
static func parents_of(state: WorldState, id: int) -> Array[int]:
	var p := state.index_of(id)
	if p != -1:
		return [state.person_mothers[p], state.person_fathers[p]]
	var record: Dictionary = state.dead.get(str(id), {})
	return [int(record.get("mother", -1)), int(record.get("father", -1))]


## Ids of a person's children, living and dead, oldest first.
static func children_of(state: WorldState, id: int) -> Array[int]:
	var found: Array[int] = []
	var born := {}
	for p: int in state.person_ids.size():
		if state.person_mothers[p] == id or state.person_fathers[p] == id:
			found.append(state.person_ids[p])
			born[state.person_ids[p]] = state.person_born[p]
	for key: String in state.dead:
		var record: Dictionary = state.dead[key]
		if int(record["mother"]) == id or int(record["father"]) == id:
			found.append(key.to_int())
			born[key.to_int()] = int(record["born"])
	found.sort_custom(func(a: int, b: int) -> bool: return born[a] < born[b])
	return found


## Living brothers and sisters (sharing at least one parent).
static func siblings_of(state: WorldState, p: int) -> Array[int]:
	var found: Array[int] = []
	var mother := state.person_mothers[p]
	var father := state.person_fathers[p]
	for q: int in state.person_ids.size():
		if q != p and ((mother != -1 and state.person_mothers[q] == mother) or (father != -1 and state.person_fathers[q] == father)):
			found.append(q)
	return found


## Too closely related to marry: parent and child, siblings, half-siblings, grandparents,
## aunts and uncles. First cousins may marry, as in many real societies, but rarely do.
static func is_close_kin(state: WorldState, a: int, b: int) -> bool:
	var parents_a := parents_of(state, a)
	var parents_b := parents_of(state, b)
	if b in parents_a or a in parents_b:
		return true
	for parent: int in parents_a:
		if parent != -1 and parent in parents_b:
			return true
	var grandparents_a := _grandparents(state, parents_a)
	var grandparents_b := _grandparents(state, parents_b)
	# A grandparent, or an aunt or uncle (the other's grandparent's child).
	if b in grandparents_a or a in grandparents_b:
		return true
	for parent: int in parents_a:
		if parent != -1 and parent in _children_of_any(state, grandparents_b):
			return true
	for parent: int in parents_b:
		if parent != -1 and parent in _children_of_any(state, grandparents_a):
			return true
	return false


static func are_cousins(state: WorldState, a: int, b: int) -> bool:
	var grandparents_a := _grandparents(state, parents_of(state, a))
	for grandparent: int in _grandparents(state, parents_of(state, b)):
		if grandparent != -1 and grandparent in grandparents_a:
			return true
	return false


static func _grandparents(state: WorldState, parents: Array[int]) -> Array[int]:
	var found: Array[int] = []
	for parent: int in parents:
		if parent != -1:
			found.append_array(parents_of(state, parent))
	return found


static func _children_of_any(state: WorldState, ids: Array[int]) -> Array[int]:
	var found: Array[int] = []
	for id: int in ids:
		if id != -1:
			for p: int in state.person_ids.size():
				if state.person_mothers[p] == id or state.person_fathers[p] == id:
					found.append(state.person_ids[p])
	return found


## "husband" or "wife" for someone of this sex.
static func partner_word(sex: String) -> String:
	return "wife" if sex == "f" else "husband"


static func pronoun(state: WorldState, p: int) -> String:
	return "she" if is_female(state, p) else "he"


static func possessive(state: WorldState, p: int) -> String:
	return "her" if is_female(state, p) else "his"


# --- Body ---------------------------------------------------------------------------

## The healthiest someone can be at an age: vitality raises it, frailty and old age lower it.
static func max_health(genome: PackedByteArray, years: int) -> int:
	var top := 80.0 + 20.0 * Genetics.express(genome, "vitality")
	if Genetics.is_frail(genome):
		top -= 30.0
	top -= maxf(years - 45.0, 0.0) * 1.2
	return clampi(roundi(top), 25, 100)


static func traits_of(state: WorldState, p: int) -> PackedStringArray:
	return state.person_traits[p].split("|", false)


static func has_trait(state: WorldState, p: int, trait_id: String) -> bool:
	return trait_id in traits_of(state, p)


## Personality forms when someone comes of age: genes lean them one way, parents another,
## and the rest is chance. Returns the two traits.
static func form_traits(state: WorldState, p: int) -> PackedStringArray:
	var genome := state.person_genomes[p]
	var temper := Genetics.express(genome, "temper")
	var social := Genetics.express(genome, "sociability")
	var curious := Genetics.express(genome, "curiosity")
	var clever := Genetics.express(genome, "intellect")
	var strong := Genetics.express(genome, "strength")
	var vital := Genetics.express(genome, "vitality")
	var weights := {
		"brave": 0.4 + temper * 0.6 + strong * 0.8,
		"fierce": 0.1 + temper * 1.6,
		"kind": 0.3 + (1.0 - temper) * 1.0 + social * 0.4,
		"cheerful": 0.2 + social * 1.4,
		"wise": 0.2 + clever * 1.2 + (1.0 - curious) * 0.3,
		"proud": 0.3 + temper * 0.5 + strong * 0.4,
		"curious": 0.1 + curious * 1.6,
		"devout": 0.6 + (1.0 - curious) * 0.6,
		"greedy": 0.3 + (1.0 - social) * 0.5,
		"lazy": 0.2 + (1.0 - vital) * 0.6,
	}
	# Children pick up their parents' ways.
	for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
		var q := state.index_of(parent)
		var parent_traits := traits_of(state, q) if q != -1 else PackedStringArray(String((state.dead.get(str(parent), {}) as Dictionary).get("traits", "")).split("|", false))
		for trait_id: String in parent_traits:
			weights[trait_id] = float(weights[trait_id]) + 0.7
	var chosen := PackedStringArray()
	for pick: int in 2:
		var total := 0.0
		for trait_id: String in TRAIT_ORDER:
			if trait_id not in chosen:
				total += float(weights[trait_id])
		var roll := state.rng.randf() * total
		for trait_id: String in TRAIT_ORDER:
			if trait_id in chosen:
				continue
			roll -= float(weights[trait_id])
			if roll <= 0.0:
				chosen.append(trait_id)
				break
		if chosen.size() <= pick:
			chosen.append(TRAIT_ORDER[pick])
	state.person_traits[p] = "|".join(chosen)
	return chosen


# --- Chiefs -------------------------------------------------------------------------

## The combined effect of a tribe chief's traits: a multiplier (default 1) or a sum (default 0).
static func chief_effect(state: WorldState, tribe_name: String, effect: String) -> float:
	var leader := state.chief_of(tribe_name)
	var multiply := effect in ["war", "gather", "starve", "split"]
	var total := 1.0 if multiply else 0.0
	if leader == -1:
		return total
	for trait_id: String in traits_of(state, leader):
		var value := float(TRAITS[trait_id].get(effect, 1.0 if multiply else 0.0))
		total = total * value if multiply else total + value
	return total


## How much the tribe looks up to someone: what the others think of them, plus age, skill and
## the traits people follow.
static func standing(state: WorldState, p: int, members: Array[int]) -> float:
	var id := state.person_ids[p]
	var opinion := 0.0
	for q: int in members:
		if q != p:
			opinion += state.bond(id, state.person_ids[q])
	var score := opinion / maxf(members.size() - 1, 1.0)
	score += minf(age(state, p), 60) * 0.5
	score += Genetics.express(state.person_genomes[p], "intellect") * 12.0
	score += state.person_skills[p][Jobs.SKILLS.find("lore")] * 0.1
	score += sqrt(maxf(state.person_wealth[p], 0.0)) * 1.2
	if state.person_status[p] == "noble":
		score += 10.0
	elif state.person_status[p] == "bonded":
		score -= 25.0
	for trait_id: String in traits_of(state, p):
		score += {"wise": 10.0, "brave": 6.0, "kind": 5.0, "proud": 4.0, "cheerful": 3.0, "lazy": -6.0, "greedy": -4.0}.get(trait_id, 0.0)
	return score


## Standing, tilted toward whoever the strongest faction would put forward: under the warriors a
## seasoned fighter, under the priests a holy one, under the merchants the rich.
static func claim(state: WorldState, p: int, members: Array[int], top: String) -> float:
	var score := standing(state, p, members)
	match top:
		"warriors":
			score += state.person_skills[p][Jobs.SKILLS.find("arms")] * 0.4 + (20.0 if state.person_jobs[p] == "guard" else 0.0)
			score += 8.0 if has_trait(state, p, "brave") or has_trait(state, p, "fierce") else 0.0
		"priests":
			score += state.person_skills[p][Jobs.SKILLS.find("lore")] * 0.4 + (20.0 if state.person_jobs[p] == "shaman" else 0.0)
			score += 10.0 if has_trait(state, p, "devout") else 0.0
		"merchants":
			score += sqrt(maxf(state.person_wealth[p], 0.0)) * 3.0 + (15.0 if state.person_jobs[p] == "merchant" else 0.0)
	return score


## Under hereditary rule: the eldest adult of the ruling house, or -1 if the house has died out here.
static func heir(state: WorldState, t: int) -> int:
	var house := state.tribe_dynasty[t]
	var best := -1
	for p: int in state.people_of(state.tribe_names[t]):
		if state.person_families[p] == house and is_adult(state, p) and state.person_detained[p] == 0:
			if best == -1 or state.person_born[p] < state.person_born[best]:
				best = p
	return best


## The tribe gathers and chooses its most respected adult, or, under hereditary rule, the eldest of
## the ruling house takes the seat. Logs the choice and returns their index.
## reason: "founding", "death", "council", "election", "inheritance", "revolution", "coup".
static func choose_chief(state: WorldState, t: int, reason: String) -> int:
	var tribe := state.tribe_names[t]
	var members := state.people_of(tribe)
	var best := -1
	if Society.flag(state, t, "hereditary") and state.tribe_dynasty[t] and reason in ["death", "council", "founding"]:
		best = heir(state, t)
		if best != -1:
			reason = "inheritance"
	if best == -1:
		var top := Society.top_faction(state, t)
		var best_score := -INF
		for p: int in members:
			if (age(state, p) < 25 and best != -1) or not is_adult(state, p) or state.person_detained[p] > 0:
				continue
			var score := claim(state, p, members, top)
			if score > best_score:
				best = p
				best_score = score
	if best == -1:
		state.tribe_chiefs[t] = -1
		return -1
	state.tribe_chiefs[t] = state.person_ids[best]
	# A house that rules by birth: the first hereditary ruler founds it, and a new one takes over
	# when the old house has died out.
	if Society.flag(state, t, "hereditary") and state.tribe_dynasty[t] != state.person_families[best]:
		state.tribe_dynasty[t] = state.person_families[best]
		state.log_event("new_dynasty", {"tribe": tribe, "house": state.person_families[best], "id": state.person_ids[best], "name": state.person_names[best]})
	state.log_event("new_chief", {
		"tribe": tribe, "id": state.person_ids[best], "name": state.person_names[best],
		"traits": state.person_traits[best].replace("|", ", "), "reason": reason, "age": age(state, best),
	})
	state.life(state.person_ids[best], "Was chosen to lead the %s." % tribe, "chief")
	return best


# --- The first people ---------------------------------------------------------------

## The first band: a few couples with their children, some young adults and an elder or two,
## from two ancestries. Each household gets a tent around the fire.
static func found_band(state: WorldState, tribe: String, couples: int = FOUNDING_COUPLES) -> void:
	var rng := state.rng
	var first_ancestry := rng.pick_index(Genetics.ANCESTRIES.size())
	var second_ancestry := (first_ancestry + 1 + rng.pick_index(Genetics.ANCESTRIES.size() - 1)) % Genetics.ANCESTRIES.size()
	var ancestry := func() -> int: return first_ancestry if rng.chance(0.6) else second_ancestry
	var year := WorldState.DAYS_PER_YEAR
	for k: int in couples:
		var man_age := rng.randi_range(19, 40)
		var woman_age := clampi(man_age + rng.randi_range(-5, 2), 17, 40)
		var family := NameGen.family_name(rng)
		var man := state.add_person(tribe, "m", -man_age * year - rng.randi_range(0, year - 1), Genetics.founder(rng, ancestry.call()), -1, -1, family, NameGen.person_name(rng))
		var woman := state.add_person(tribe, "f", -woman_age * year - rng.randi_range(0, year - 1), Genetics.founder(rng, ancestry.call()), -1, -1, NameGen.family_name(rng), NameGen.person_name(rng))
		var man_id := state.person_ids[man]
		var woman_id := state.person_ids[woman]
		state.person_partners[man] = woman_id
		state.person_partners[woman] = man_id
		state.change_bond(man_id, woman_id, 60)
		state.change_love(man_id, woman_id, 70)
		var tent := state.add_building(tribe, "tent", Buildings.free_slot(state, tribe, "tent")).done(state)
		state.person_homes[man] = state.building_ids[tent]
		state.person_homes[woman] = state.building_ids[tent]
		var children := rng.randi_range(0, mini(3, (woman_age - 17) / 3 + 1))
		for c: int in children:
			var child_age := rng.randi_range(0, woman_age - 17)
			var genome: PackedByteArray = Genetics.inherit(rng, state.person_genomes[woman], state.person_genomes[man])["genome"]
			var child := state.add_person(tribe, "f" if rng.chance(0.5) else "m", -child_age * year - rng.randi_range(0, year - 1), genome, woman_id, man_id, family, NameGen.person_name(rng))
			state.person_homes[child] = state.building_ids[tent]
			state.change_bond(state.person_ids[child], woman_id, 50)
			state.change_bond(state.person_ids[child], man_id, 45)
	var spare := state.add_building(tribe, "tent", Buildings.free_slot(state, tribe, "tent")).done(state)
	for k: int in rng.randi_range(2, 4):
		var young := state.add_person(tribe, "f" if rng.chance(0.5) else "m", -rng.randi_range(16, 23) * year - rng.randi_range(0, year - 1), Genetics.founder(rng, ancestry.call()), -1, -1, NameGen.family_name(rng), NameGen.person_name(rng))
		state.person_homes[young] = state.building_ids[spare]
	for k: int in rng.randi_range(1, 2):
		var elder := state.add_person(tribe, "f" if rng.chance(0.5) else "m", -rng.randi_range(55, 64) * year - rng.randi_range(0, year - 1), Genetics.founder(rng, ancestry.call()), -1, -1, NameGen.family_name(rng), NameGen.person_name(rng))
		state.person_homes[elder] = state.building_ids[spare]
	var members := state.people_of(tribe)
	for p: int in members:
		var years := age(state, p)
		state.person_health[p] = max_health(state.person_genomes[p], years)
		if years >= 15:
			form_traits(state, p)
		# Everyone already knows a little of the work they grew up with.
		for s: int in Jobs.SKILLS.size():
			state.person_skills[p][s] = clampi(rng.randi_range(0, 8) + maxi(years - 14, 0), 0, 40) if years >= 12 and s < 6 else 0
		# Some families came with more than others.
		state.person_wealth[p] = rng.randi_range(0, 12) if years >= 16 else 0
		state.life(state.person_ids[p], "Born into a wandering band, before the valley had a name.", "birth")
	# Old friendships and quarrels from the years of wandering.
	for k: int in members.size() * 3:
		var a := members[rng.pick_index(members.size())]
		var b := members[rng.pick_index(members.size())]
		if a != b:
			state.change_bond(state.person_ids[a], state.person_ids[b], rng.randi_range(-15, 30))
	choose_chief(state, state.tribe_index(tribe), "founding")


# --- For the inspector and the AI ---------------------------------------------------

## The job someone does, or what they do instead: "hunter", "apprentice hunter", "child", "elder".
static func role(state: WorldState, p: int) -> String:
	var job := state.person_jobs[p]
	match stage(state, p):
		"infant":
			return "baby"
		"child":
			return "child"
		"youth":
			return "apprentice " + Jobs.name_of(job) if job else "youth"
	if job:
		return Jobs.name_of(job)
	return "elder" if age(state, p) >= RETIRE_AT else "without work"


## What someone is up to right now, for the view and the inspector: "working", "sick",
## "mourning", "nursing", "playing", "resting", "teaching", "courting", "idle".
static func activity(state: WorldState, p: int) -> String:
	if state.person_sick[p] > 0:
		return "sick"
	var s := stage(state, p)
	if s == "infant":
		return "infant"
	if s == "child":
		return "playing"
	if state.person_grief[p] > 6:
		return "mourning"
	if state.person_due[p] != -1 and state.person_due[p] - state.tick < 45:
		return "resting"
	if state.person_jobs[p]:
		return "working"
	if age(state, p) >= RETIRE_AT:
		return "teaching"
	return "idle"


## Everything worth knowing about a person, for the inspector and the AI.
static func describe(state: WorldState, p: int) -> Dictionary:
	var tribe_name := state.person_tribes[p]
	var t := state.tribe_index(tribe_name)
	var id := state.person_ids[p]
	var needs := {}
	for need: String in Needs.NAMES:
		needs[need] = snappedf(Needs.get_need(state, t, need), 0.01)
	var neighbors: Array[Dictionary] = []
	for other: String in state.tribe_names:
		var value := state.relation(tribe_name, other)
		if other != tribe_name and value != 0:
			neighbors.append({"tribe": other, "relation": value, "word": WorldState.relation_word(value)})
	neighbors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absi(a["relation"]) > absi(b["relation"]))
	var friends: Array[String] = []
	var rivals: Array[String] = []
	for entry: Dictionary in strongest_bonds(state, id, 6):
		if int(entry["value"]) >= 30:
			friends.append(String(entry["name"]))
		elif int(entry["value"]) <= -30:
			rivals.append(String(entry["name"]))
	var family := {}
	var partner := state.index_of(state.person_partners[p])
	if partner != -1:
		family[partner_word(state.person_sexes[partner])] = state.person_names[partner]
	var kids := children_of(state, id)
	if not kids.is_empty():
		var alive := kids.filter(func(k: int) -> bool: return state.is_alive(k)).size()
		family["children"] = "%d living, %d lost" % [alive, kids.size() - alive] if alive < kids.size() else "%d" % alive
	for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
		if parent != -1:
			family["mother" if parent == state.person_mothers[p] else "father"] = "%s (%s)" % [name_of(state, parent), "alive" if state.is_alive(parent) else "dead"]
	var story: Array = state.lives.get(str(id), [])
	var recent_life: Array[String] = []
	for entry: Dictionary in story.slice(maxi(story.size() - 5, 0)):
		recent_life.append("%s: %s" % [WorldState.date_text(int(entry["t"])), entry["text"]])
	var recent: Array[Dictionary] = []
	for event: Dictionary in EventText.major(state.events).slice(-6):
		recent.append({"year": WorldState.year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
	var water := state.tribe_water[t]
	return {
		"name": full_name(state, p),
		"age": age(state, p),
		"sex": "woman" if is_female(state, p) else "man",
		"stage": stage(state, p),
		"role": role(state, p),
		"is_chief": state.tribe_chiefs[t] == id,
		"traits": Array(traits_of(state, p)),
		"born_with": Genetics.notable(state.person_genomes[p]),
		"health": state.person_health[p],
		"mood": state.person_mood[p],
		"doing": activity(state, p),
		"pregnant": state.person_due[p] != -1,
		"family": family,
		"friends": friends,
		"rivals": rivals,
		"life_so_far": recent_life,
		"tribe": tribe_name,
		"tribe_population": state.tribe_population[t],
		"needs": needs,
		"tribe_mood": Needs.mood_word(Needs.mood(state, t)),
		"drinks_from": state.water_names[water],
		"water_fullness": snappedf(state.water_level[water], 0.01),
		"neighbors": neighbors,
		"in_drought": state.drought_months_left > 0,
		"season": state.season(),
		"god_kindness": state.kindness,
		"year": state.year(),
		"recent_events": recent,
	}


## The people someone feels most strongly about: [{"id", "name", "value", "love", "alive"}], strongest first.
static func strongest_bonds(state: WorldState, id: int, limit: int = 8) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var prefix := "%d|" % id
	var suffix := "|%d" % id
	for key: String in state.bonds:
		if key.begins_with(prefix) or key.ends_with(suffix):
			var parts := key.split("|")
			var other := parts[1].to_int() if parts[0].to_int() == id else parts[0].to_int()
			found.append({"id": other, "name": name_of(state, other), "value": int(state.bonds[key]), "love": state.love(id, other)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absi(a["value"]) + int(a["love"]) > absi(b["value"]) + int(b["love"]) or (absi(a["value"]) + int(a["love"]) == absi(b["value"]) + int(b["love"]) and int(a["id"]) < int(b["id"])))
	return found.slice(0, limit)
