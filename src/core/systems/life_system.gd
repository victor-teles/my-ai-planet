class_name LifeSystem
extends SimSystem
## The course of a life. Every day, babies that are due are born (each with a genome drawn from
## both parents). Every month, for everyone: health rises or falls with food, water, shelter and
## sickness; fevers come and go and spread at home; some die (of age, sickness, hunger,
## accidents at work, childbirth); couples may conceive; the young come of age and their
## personality shows; orphans are taken in; and everyone's mood follows their life.

const PREGNANCY_DAYS := 268
const TWIN_CHANCE := 0.015
const CHILDBIRTH_RISK := 0.012
const CONCEPTION_CHANCE := 0.18 ## per month for a fertile couple, before genes, food and age
## Families shrink once the island holds more than (this - 1) of what it feeds well (a tenth: about
## 26 people): a few bands grow freely, a crowded island slowly. With famines no longer starving
## whole bands, 1.3 let the First Fires century overshoot (about 145 people at year 100, not 120).
const FULL_FAMILIES := 1.1
const BIRTH_SPACING_DAYS := 380 ## nursing keeps most mothers from conceiving again soon
const SICK_CHANCE := 0.008
const WINTER_SICK_CHANCE := 0.014
const CONTAGION := 0.05 ## per sick housemate
const EPIDEMIC_SHARE := 0.25 ## share of a tribe sick at once that makes it an epidemic
const EPIDEMIC_QUIET := 2 * WorldState.DAYS_PER_YEAR ## a fever that lingers is one epidemic, not one a month
const NAMED_AFTER_CHANCE := 0.3
## By age: families grow smaller as children stop dying young and start costing schooling.
const AGE_BIRTHS: Array[float] = [1.0, 1.0, 0.95, 0.8, 0.65]


func get_id() -> String:
	return "life"


func update(state: WorldState) -> void:
	_births(state)
	if state.is_month_start():
		_monthly(state)


# --- Births -------------------------------------------------------------------------

func _births(state: WorldState) -> void:
	var mothers: Array[int] = []
	for p: int in state.person_ids.size():
		if state.person_due[p] == state.tick:
			mothers.append(state.person_ids[p])
	for id: int in mothers:
		var p := state.index_of(id)
		if p != -1:
			give_birth(state, p)


static func give_birth(state: WorldState, mother: int) -> Array[int]:
	var mother_id := state.person_ids[mother]
	var father_id := state.person_baby_fathers[mother]
	state.person_due[mother] = -1
	state.person_baby_fathers[mother] = -1
	var father_genome := _genome_of(state, father_id)
	if father_genome.is_empty():
		father_genome = state.person_genomes[mother]
	var tribe := state.person_tribes[mother]
	var t := state.tribe_index(tribe)
	var father := state.index_of(father_id)
	var family := state.person_families[father] if father != -1 else String((state.dead.get(str(father_id), {}) as Dictionary).get("family", state.person_families[mother]))
	var count := 2 if state.rng.chance(TWIN_CHANCE) else 1
	var babies: Array[int] = []
	for k: int in count:
		var heredity := Genetics.inherit(state.rng, state.person_genomes[mother], father_genome)
		var sex := "f" if state.rng.chance(0.5) else "m"
		var named_after := _honored_name(state, mother_id, father_id, sex)
		var given := named_after if named_after else NameGen.person_name(state.rng, Language.of(state, t))
		var baby := state.add_person(tribe, sex, state.tick, heredity["genome"], mother_id, father_id, family, given)
		var baby_id := state.person_ids[baby]
		# Noble blood needs both parents, or the ruling house's name: one noble parent made, within
		# a few generations, a tribe of nothing but nobles.
		var both_noble := state.person_status[mother] == "noble" and father != -1 and state.person_status[father] == "noble"
		var royal := t != -1 and state.tribe_dynasty[t] != "" and family == state.tribe_dynasty[t] and (state.person_status[mother] == "noble" or (father != -1 and state.person_status[father] == "noble"))
		if both_noble or royal:
			state.person_status[baby] = "noble"
		babies.append(baby_id)
		state.person_homes[baby] = state.person_homes[mother]
		state.person_health[baby] = People.max_health(state.person_genomes[baby], 0) - state.rng.randi_range(0, 10)
		state.change_bond(baby_id, mother_id, 60)
		if father_id != -1:
			state.change_bond(baby_id, father_id, 50)
		var father_name := People.name_of(state, father_id)
		var data := {
			"tribe": tribe, "id": baby_id, "name": given, "sex": sex,
			"mother": mother_id, "mother_name": state.person_names[mother],
			"father": father_id, "father_name": father_name,
		}
		if named_after:
			data["named_after"] = "%s late %s" % ["her" if sex == "f" else "his", _relation_word(state, mother_id, father_id, named_after)]
		if count == 2:
			data["twin"] = 1
		state.log_event("birth", data)
		var story := "Born in %s to %s%s, in the %s." % [WorldState.MONTH_NAMES[state.month()].to_lower(), state.person_names[mother], " and " + father_name if father_name else "", tribe]
		state.life(baby_id, story, "birth")
		var mutations: Array = heredity["mutations"]
		if not mutations.is_empty():
			state.life(baby_id, "Born with a new mutation (%s)." % ", ".join(mutations.map(func(g: String) -> String: return String(Genetics.INFO[g]["name"]).to_lower())), "dna")
		if Genetics.is_frail(state.person_genomes[baby]):
			state.life(baby_id, "Inherited frailty from both parents.", "dna")
		var child_word := "daughter" if sex == "f" else "son"
		state.life(mother_id, "Gave birth to a %s, %s." % [child_word, given], "birth")
		if father != -1:
			state.life(father_id, "Became the father of a %s, %s." % [child_word, given], "birth")
	# Giving birth is dangerous; a healer makes it much safer.
	var risk := CHILDBIRTH_RISK * (1.0 - 0.6 * _care(state, t)) * (2.0 if People.age(state, mother) >= 38 else 1.0) * (1.5 if count == 2 else 1.0)
	if Genetics.is_frail(state.person_genomes[mother]):
		risk *= 2.0
	if state.rng.chance(risk):
		state.kill_person(mother, "childbirth")
	return babies


static func _genome_of(state: WorldState, id: int) -> PackedByteArray:
	var p := state.index_of(id)
	if p != -1:
		return state.person_genomes[p]
	var record: Dictionary = state.dead.get(str(id), {})
	return Genetics.from_hex(String(record.get("genome", ""))) if record.has("genome") else PackedByteArray()


## Sometimes a baby is named after a dead grandparent (or aunt or uncle) of the same sex.
static func _honored_name(state: WorldState, mother_id: int, father_id: int, sex: String) -> String:
	if not state.rng.chance(NAMED_AFTER_CHANCE):
		return ""
	var candidates: Array[String] = []
	for parent: int in [mother_id, father_id]:
		for grandparent: int in People.parents_of(state, parent):
			var record: Dictionary = state.dead.get(str(grandparent), {})
			if not record.is_empty() and String(record["sex"]) == sex:
				candidates.append(String(record["name"]))
	if candidates.is_empty():
		return ""
	return candidates[state.rng.pick_index(candidates.size())]


static func _relation_word(state: WorldState, mother_id: int, father_id: int, honored: String) -> String:
	for parent: int in [mother_id, father_id]:
		for grandparent: int in People.parents_of(state, parent):
			var record: Dictionary = state.dead.get(str(grandparent), {})
			if not record.is_empty() and String(record["name"]) == honored:
				return "grandmother %s" % honored if String(record["sex"]) == "f" else "grandfather %s" % honored
	return "kin %s" % honored


## 0..1: how well the tribe's healers can look after the sick.
static func _care(state: WorldState, t: int) -> float:
	if t == -1:
		return 0.0
	var healers := float(state.tribe_work[t].get("healer", 0.0))
	var hut := 1.3 if state.count_buildings(state.tribe_names[t], "healer_hut") > 0 else 1.0
	hut *= state.tech_bonus(t, "care")
	return clampf(healers * 30.0 * hut / maxf(state.tribe_population[t], 1.0), 0.0, 1.0)


# --- Every month --------------------------------------------------------------------

func _monthly(state: WorldState) -> void:
	var ids := state.person_ids.duplicate()
	var homes_sick := {}
	for p: int in state.person_ids.size():
		if state.person_sick[p] > 0 and state.person_homes[p] != -1:
			homes_sick[state.person_homes[p]] = int(homes_sick.get(state.person_homes[p], 0)) + 1
	var crowded := _crowded_homes(state)
	for id: int in ids:
		var p := state.index_of(id)
		if p == -1:
			continue
		_grow_up(state, p)
		_health(state, p, homes_sick, crowded)
		if _maybe_die(state, p):
			continue
		_conceive(state, p)
	_orphans(state)
	_moods(state)
	_epidemics(state)
	for t: int in state.tribe_count():
		state.tribe_hungry_days[t] = 0


func _grow_up(state: WorldState, p: int) -> void:
	if state.person_grief[p] > 0:
		state.person_grief[p] -= 1
	if state.person_traits[p].is_empty() and People.age(state, p) >= 15:
		var traits := People.form_traits(state, p)
		var words := "%s and %s" % [traits[0], traits[1]]
		state.log_event("coming_of_age", {"tribe": state.person_tribes[p], "id": state.person_ids[p], "name": state.person_names[p], "traits": words})
		state.life(state.person_ids[p], "Came of age: %s." % words, "growth")


func _crowded_homes(state: WorldState) -> Dictionary:
	var residents := {}
	for p: int in state.person_ids.size():
		var home := state.person_homes[p]
		if home != -1:
			residents[home] = int(residents.get(home, 0)) + 1
	var crowded := {}
	for b: int in state.building_ids.size():
		var id := state.building_ids[b]
		if int(residents.get(id, 0)) > Buildings.capacity(state.building_types[b]):
			crowded[id] = true
	return crowded


func _health(state: WorldState, p: int, homes_sick: Dictionary, crowded: Dictionary) -> void:
	var t := state.tribe_index(state.person_tribes[p])
	var genome := state.person_genomes[p]
	var years := People.age(state, p)
	var fragile := 1.5 if years < People.INFANT_UNTIL or years >= 65 else (1.2 if years < People.CHILD_UNTIL else 1.0)
	var health := state.person_health[p] + 6
	var hungry := state.tribe_hungry_days[t]
	if hungry > 0:
		var build := Genetics.express(genome, "build")
		health -= roundi(hungry * 1.3 * fragile * (1.25 - 0.5 * build) * People.chief_effect(state, state.person_tribes[p], "starve")) + 6
	var water := Needs.water(state, t)
	if water < 0.5:
		health -= roundi((0.5 - water) * 50.0 * fragile)
	if state.season() == "winter":
		var cold := float(state.world.get("winter", 1.0))
		if state.person_homes[p] == -1:
			health -= roundi(8 * fragile * cold)
		else:
			health -= roundi(3 * fragile * cold * (1.0 - state.tribe_cloth[t]))
	var home := state.person_homes[p]
	if state.person_sick[p] > 0:
		state.person_sick[p] -= WorldState.DAYS_PER_MONTH
		health -= roundi(12 * fragile * (1.0 - 0.5 * _care(state, t)))
		if state.person_sick[p] <= 0:
			state.person_sick[p] = 0
	else:
		var chance := SICK_CHANCE + (WINTER_SICK_CHANCE if state.season() == "winter" else 0.0)
		chance += 0.025 * (1.0 - Genetics.express(genome, "vitality"))
		chance += 0.015 if crowded.has(home) else 0.0
		chance += 0.02 if Genetics.is_frail(genome) else 0.0
		chance += CONTAGION * int(homes_sick.get(home, 0)) if home != -1 else 0.0
		chance *= fragile * float(state.world.get("sickness", 1.0)) * state.tech_bonus(t, "sickness")
		chance *= 1.0 + state.pollution / 80.0
		if state.rng.chance(chance):
			state.person_sick[p] = state.rng.randi_range(8, 45)
	state.person_health[p] = clampi(health, 0, People.max_health(genome, years))


## Returns true if they died.
func _maybe_die(state: WorldState, p: int) -> bool:
	var t := state.tribe_index(state.person_tribes[p])
	var genome := state.person_genomes[p]
	var years := People.age(state, p)
	var health := state.person_health[p]
	if health <= 0:
		state.kill_person(p, _hardship(state, t))
		return true
	var effective_age := years - (Genetics.express(genome, "longevity") - 0.5) * 16.0 + (12.0 if Genetics.is_frail(genome) else 0.0)
	var yearly := 0.003 + 0.0011 * exp((effective_age - 30.0) / 9.5)
	if years < 1:
		yearly = 0.05
	elif years < 5:
		yearly = 0.022
	elif years < 15:
		yearly = 0.005
	var age_risk := yearly / 12.0
	var sick_risk := 0.0
	if state.person_sick[p] > 0:
		var fragile := 2.5 if years < People.INFANT_UNTIL or years >= 65 else 1.0
		sick_risk = 0.006 * fragile * (1.6 - Genetics.express(genome, "vitality")) * (1.0 - 0.6 * _care(state, t))
	var weak_risk := (25.0 - health) / 25.0 * 0.15 if health < 25 else 0.0
	var job := state.person_jobs[p]
	var accident_risk := float(Jobs.DEFINITIONS[job]["danger"]) if Jobs.DEFINITIONS.has(job) else 0.0
	if People.has_trait(state, p, "brave"):
		accident_risk *= 1.3
	var total := age_risk + sick_risk + weak_risk + accident_risk
	if not state.rng.chance(total):
		return false
	var roll := state.rng.randf() * total
	if roll < age_risk:
		state.kill_person(p, "old age" if years >= 50 else ("sickness" if years < 15 or state.rng.chance(0.8) else "accident"), {"while": "on a journey"} if years >= 15 and years < 50 else {})
	elif roll < age_risk + sick_risk:
		state.kill_person(p, "sickness")
	elif roll < age_risk + sick_risk + weak_risk:
		state.kill_person(p, _hardship(state, t))
	else:
		state.kill_person(p, "accident", {"while": _accident_place(job)})
	return true


func _hardship(state: WorldState, t: int) -> String:
	if state.tribe_hungry_days[t] > 0:
		return "hunger"
	if Needs.water(state, t) < 0.5:
		return "thirst"
	return "sickness"


func _accident_place(job: String) -> String:
	match job:
		"hunter":
			return "on the hunt"
		"woodcutter":
			return "felling a tree"
		"quarrier":
			return "at the quarry"
		"builder":
			return "while building"
		"fisher":
			return "on the water"
	return "at work"


func _conceive(state: WorldState, p: int) -> void:
	if not People.is_female(state, p) or state.person_due[p] != -1:
		return
	var years := People.age(state, p)
	if years < People.ADULT_AT or years > 45:
		return
	var partner := state.index_of(state.person_partners[p])
	if partner == -1 or People.is_female(state, partner) or state.person_tribes[partner] != state.person_tribes[p]:
		return
	if state.person_detained[p] > 0 or state.person_detained[partner] > 0:
		return
	var id := state.person_ids[p]
	var children := 0
	var youngest := 1 << 30
	for q: int in state.person_ids.size():
		if state.person_mothers[q] == id:
			children += 1
			youngest = mini(youngest, state.tick - state.person_born[q])
	if youngest < BIRTH_SPACING_DAYS:
		return
	var t := state.tribe_index(state.person_tribes[p])
	var chance := CONCEPTION_CHANCE
	chance *= (0.5 + Genetics.express(state.person_genomes[p], "fertility")) * (0.5 + Genetics.express(state.person_genomes[partner], "fertility"))
	chance *= 0.3 + 0.7 * Needs.food(state, t)
	chance *= 0.6 + 0.4 * Needs.shelter(state, t)
	chance *= [1.2, 1.15, 1.05, 0.9, 0.7, 0.45, 0.3][mini(children, 6)]
	if years > 40:
		chance *= 0.3
	elif years > 35:
		chance *= 0.6
	if state.person_grief[p] > 0 or state.person_health[p] < 40:
		chance *= 0.3
	chance *= Society.effect(state, t, "births") * AGE_BIRTHS[state.age_of(t)]
	# As the island fills, families grow smaller.
	chance *= clampf(FULL_FAMILIES - state.total_population() / state.carrying_capacity(), 0.15, 1.0)
	if Society.flag(state, t, "birth_permits") and not _permitted(state, p, partner):
		return
	if state.rng.chance(chance):
		state.person_due[p] = state.tick + PREGNANCY_DAYS + state.rng.randi_range(0, 14)
		state.person_baby_fathers[p] = state.person_partners[p]
		state.life(id, "Is expecting a child with %s." % state.person_names[partner], "family")


## Under birth permits, the state reads both partners' blood: carriers of frailty, the frail and the
## disloyal are refused. The first refusal goes into their life story.
static func _permitted(state: WorldState, p: int, partner: int) -> bool:
	var refused := ""
	for q: int in [p, partner]:
		if Genetics.frailty_copies(state.person_genomes[q]) > 0:
			refused = "their blood"
		elif state.person_loyalty[q] < 40:
			refused = "their loyalty"
	if refused.is_empty():
		return true
	var story: Array = state.lives.get(str(state.person_ids[p]), [])
	if story.is_empty() or not String((story[-1] as Dictionary)["text"]).begins_with("Was refused a birth permit"):
		var text := "Was refused a birth permit for %s." % refused
		state.life(state.person_ids[p], text, "society")
		state.life(state.person_ids[partner], text, "society")
	return false


## A child left with no adult at home is taken in: by a grandparent, an aunt or uncle, a grown
## sibling, or failing that the kindest family of the tribe.
func _orphans(state: WorldState) -> void:
	var adults_at_home := {}
	for p: int in state.person_ids.size():
		if People.is_adult(state, p) and state.person_homes[p] != -1:
			adults_at_home[state.person_homes[p]] = true
	for p: int in state.person_ids.size():
		if People.is_adult(state, p) or state.is_alive(state.person_mothers[p]) or state.is_alive(state.person_fathers[p]):
			continue
		if state.person_homes[p] != -1 and adults_at_home.has(state.person_homes[p]):
			continue
		var adopter := _adopter(state, p)
		if adopter == -1:
			continue
		state.person_homes[p] = state.person_homes[adopter]
		state.change_bond(state.person_ids[p], state.person_ids[adopter], 40)
		state.log_event("adoption", {"tribe": state.person_tribes[p], "id": state.person_ids[p], "name": state.person_names[p], "by": state.person_names[adopter], "by_id": state.person_ids[adopter]})
		state.life(state.person_ids[p], "Orphaned, was taken in by %s." % state.person_names[adopter], "family")
		state.life(state.person_ids[adopter], "Took in the orphan %s." % state.person_names[p], "family")


func _adopter(state: WorldState, child: int) -> int:
	var tribe := state.person_tribes[child]
	var parents := People.parents_of(state, state.person_ids[child])
	var grandparents: Array[int] = []
	for parent: int in parents:
		if parent != -1:
			grandparents.append_array(People.parents_of(state, parent))
	var best := -1
	var best_score := -INF
	for q: int in state.people_of(tribe):
		if not People.is_adult(state, q) or state.person_homes[q] == -1 or People.age(state, q) > 70:
			continue
		var id := state.person_ids[q]
		var score := 0.0
		if id in grandparents:
			score += 100.0
		var q_parents := People.parents_of(state, id)
		for gp: int in grandparents:
			if gp != -1 and gp in q_parents:
				score += 80.0 # an aunt or uncle
		for parent: int in parents:
			if parent != -1 and parent in q_parents:
				score += 70.0 # a grown sibling
		score += state.bond(id, state.person_ids[child]) * 0.5
		for parent: int in parents:
			score += state.bond(id, parent) * 0.3
		if state.person_partners[q] != -1:
			score += 15.0
		if People.has_trait(state, q, "kind"):
			score += 10.0
		if score > best_score:
			best = q
			best_score = score
	return best


## Everyone's mood: the tribe's needs, then their own life: a partner, children, friends,
## grief, sickness and hunger.
func _moods(state: WorldState) -> void:
	var friends := {}
	var enemies := {}
	for key: String in state.bonds:
		var value := int(state.bonds[key])
		if absi(value) < 40:
			continue
		var table := friends if value > 0 else enemies
		for part: String in key.split("|"):
			table[part.to_int()] = int(table.get(part.to_int(), 0)) + 1
	var children := {}
	for p: int in state.person_ids.size():
		for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
			if parent != -1:
				children[parent] = int(children.get(parent, 0)) + 1
	var tribe_mood := {}
	var credit := {}
	for t: int in state.tribe_count():
		var faith := minf(float(state.tribe_work[t].get("shaman", 0.0)), 1.0) * 6.0
		tribe_mood[state.tribe_names[t]] = 30.0 + 40.0 * Needs.mood(state, t) + faith + Society.effect(state, t, "mood") - state.pollution / 8.0
		credit[state.tribe_names[t]] = Society.flag(state, t, "social_credit")
	for p: int in state.person_ids.size():
		var id := state.person_ids[p]
		var mood := float(tribe_mood[state.person_tribes[p]])
		if state.person_partners[p] != -1:
			mood += 10.0
		mood += mini(int(children.get(id, 0)), 4) * 3.0
		mood += mini(int(friends.get(id, 0)), 5) * 3.0
		mood -= mini(int(enemies.get(id, 0)), 3) * 5.0
		if state.person_grief[p] > 0:
			mood -= 25.0
		if state.person_sick[p] > 0:
			mood -= 15.0
		if state.person_health[p] < 50:
			mood -= 10.0
		if People.has_trait(state, p, "cheerful"):
			mood += 8.0
		match state.person_status[p]:
			"noble":
				mood += 8.0
			"bonded":
				mood -= 15.0
		if state.person_detained[p] > 0:
			mood -= 30.0
		if credit[state.person_tribes[p]] and People.is_adult(state, p):
			mood += 6.0 if state.person_loyalty[p] >= 60 else -10.0
		state.person_mood[p] = clampi(roundi(mood), 0, 100)


func _epidemics(state: WorldState) -> void:
	for t: int in state.tribe_count():
		var tribe := state.tribe_names[t]
		var sick := 0
		for p: int in state.person_ids.size():
			if state.person_tribes[p] == tribe and state.person_sick[p] > 0:
				sick += 1
		if sick >= 5 and sick >= state.tribe_population[t] * EPIDEMIC_SHARE and state.ticks_since("epidemic", tribe, EPIDEMIC_QUIET) > EPIDEMIC_QUIET:
			state.log_event("epidemic", {"tribe": tribe, "sick": sick})
