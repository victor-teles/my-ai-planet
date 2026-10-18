class_name RelationsSystem
extends SimSystem
## The life of the tribes. Monthly: a tribe without a chief gathers and chooses one, and a
## starving tribe may raid a well-fed neighbor's stores.
## Yearly: the tribes' feelings for each other shift (sharing a full spring makes neighbors,
## sharing a failing one makes rivals, the hungry envy the fed, hunters of two big tribes compete
## for the same woods, the grudges and friendships of their people add up, chiefs push it one way
## or the other); rivals may go to war, fought by real people who may not come home; kind chiefs
## send gifts; friends may merge when one has grown too small; and when a tribe outgrows its land,
## a restless young adult may lead their family and friends away to found a new one.
## From the Age of Bronze, a ruler who wins a war decisively may make the loser a vassal that pays
## tribute; vassals rise up when they can, and loyal old vassals are absorbed into their overlord.

const FADE := 3 ## relations drift this much toward 0 every year
const SHARED_WATER_GOOD := 2
const SHARED_WATER_BAD := -8
const ENVY := -4 ## a hungry tribe toward a well-fed one
const CROWDED_VALLEY := 90 ## beyond this many people the tribes start to feel the hills are too full
const CROWDING_PER_POINT := 50 ## more people per point of yearly ill will
const INCIDENT_CHANCE := 0.2 ## per tribe, per year, with a tribe it isn't close friends with
const INCIDENTS: Array[String] = [
	"a quarrel over a deer", "a stolen fishing spot", "an insult at the midsummer gathering",
	"a broken promise of marriage", "a fight over firewood", "trampled fields",
]
const WAR_AT := -45
const WAR_CHANCE := 0.25
const SAME_WOODS := -3 ## two tribes each with this many hunters and foragers' work compete for game
const SAME_WOODS_WORK := 10.0
const GRUDGES_PER_POINT := 40 ## summed feelings between two tribes' people per point of relation
const RAID_HUNGRY_DAYS := 12.0 ## stores per person below which a tribe may raid
const RAID_CHANCE := 0.12 ## per month
const RAID_TAKES := 0.25 ## share of the victim's stores carried off
const RAID_ANGER := -22
const FIGHTING_AGE := [16, 45]
const LOSER_FALLEN := 0.14 ## share of the losing side's fighters who die
const WINNER_FALLEN := 0.05
const WAR_PLUNDER_DAYS := 60.0
const WAR_EXHAUSTION := 40 ## a war releases some of the hatred that started it
const MERGE_AT := 25
const MERGE_CHANCE := 0.35
const MERGE_SMALL := 9 ## a tribe this small (or a quarter of its friend, if under 20) may join its friend
const MERGE_SETTLED_YEARS := 12 ## a young tribe holds together this long unless it is tiny
const SPLIT_AT := 60 ## people, or fewer when there's no room
const SPLIT_CHANCE := 0.45
const MIN_FOLLOWERS := 14
const CHIEF_STEPS_DOWN_AT := 74
const VASSAL_AT := 1.3 ## how much stronger a winner must be to make the loser a vassal
const REVOLT_AT := -40 ## a vassal this bitter may rise up
const ANNEX_YEARS := 25 ## a loyal vassal this long may be absorbed


func get_id() -> String:
	return "relations"


func get_interval() -> int:
	return WorldState.DAYS_PER_MONTH


func update(state: WorldState) -> void:
	for t: int in state.tribe_count():
		if state.chief_of(state.tribe_names[t]) == -1:
			People.choose_chief(state, t, "death" if state.tribe_chiefs[t] != -1 or state.tick > 0 else "founding")
	_remove_empty_tribes(state)
	_raids(state)
	if state.month() != 0:
		return
	for t: int in state.tribe_count():
		var chief := state.chief_of(state.tribe_names[t])
		var for_life := Society.flag(state, t, "hereditary") and Society.top_faction(state, t) != "council"
		if chief != -1 and People.age(state, chief) >= CHIEF_STEPS_DOWN_AT and not for_life:
			state.life(state.person_ids[chief], "Stepped down as chief, grown old.", "chief")
			state.tribe_chiefs[t] = -1
			People.choose_chief(state, t, "council")
	var grudges := _grudges(state)
	for i: int in state.tribe_count():
		for j: int in range(i + 1, state.tribe_count()):
			_drift(state, i, j, int(grudges.get(WorldState.relation_key(state.tribe_names[i], state.tribe_names[j]), 0)))
	_incidents(state)
	_wars(state)
	_vassals(state)
	_gifts(state)
	_merges(state)
	_splits(state)
	_remove_empty_tribes(state)


func _remove_empty_tribes(state: WorldState) -> void:
	for t: int in range(state.tribe_count() - 1, -1, -1):
		if state.tribe_population[t] <= 0:
			state.log_event("tribe_extinct", {"tribe": state.tribe_names[t]})
			state.remove_tribe(t)


## How many people the island holds before its tribes feel crowded: more as farming and the later
## ages make each field and street feed more.
func _room(state: WorldState) -> int:
	var age := 0
	for t: int in state.tribe_count():
		age = maxi(age, state.age_of(t))
	return roundi(CROWDED_VALLEY * (1.0 + 0.5 * age))


## What the people of each pair of tribes feel for each other, summed: "A|B" -> total.
func _grudges(state: WorldState) -> Dictionary:
	var sums := {}
	for key: String in state.bonds:
		var parts := key.split("|")
		var a := state.index_of(parts[0].to_int())
		var b := state.index_of(parts[1].to_int())
		if a == -1 or b == -1 or state.person_tribes[a] == state.person_tribes[b]:
			continue
		var pair := WorldState.relation_key(state.person_tribes[a], state.person_tribes[b])
		# Grudges are remembered longer than kindness.
		var value := int(state.bonds[key])
		sums[pair] = int(sums.get(pair, 0)) + (value * 2 if value < 0 else value / 2)
	return sums


func _drift(state: WorldState, i: int, j: int, grudges: int) -> void:
	var a := state.tribe_names[i]
	var b := state.tribe_names[j]
	var value := state.relation(a, b)
	value -= signi(value) * mini(absi(value), FADE)
	value += roundi(People.chief_effect(state, a, "relation") + People.chief_effect(state, b, "relation"))
	if state.tribe_water[i] == state.tribe_water[j]:
		value += SHARED_WATER_GOOD if Needs.water(state, i) >= 1.0 else SHARED_WATER_BAD
	var food_i := Needs.food(state, i)
	var food_j := Needs.food(state, j)
	if (food_i < 0.4 and food_j > 0.8) or (food_j < 0.4 and food_i > 0.8):
		value += ENVY
	value -= maxi(state.total_population() - _room(state), 0) / CROWDING_PER_POINT
	# Families joined by marriage soften old grudges.
	value += mini(_marriages_between(state, a, b), 2)
	# What their people think of each other.
	value += clampi(grudges / GRUDGES_PER_POINT, -5, 2)
	var wild_i := float(state.tribe_work[i].get("hunter", 0.0)) + float(state.tribe_work[i].get("forager", 0.0))
	var wild_j := float(state.tribe_work[j].get("hunter", 0.0)) + float(state.tribe_work[j].get("forager", 0.0))
	if wild_i >= SAME_WOODS_WORK and wild_j >= SAME_WOODS_WORK:
		value += SAME_WOODS
	state.set_relation(a, b, value)


## Now and then something happens between two tribes that aren't close: a quarrel over a deer, an
## insult at the gathering. Proud and fierce chiefs make more of it.
func _incidents(state: WorldState) -> void:
	for tribe: String in state.tribe_names.duplicate():
		var chance := INCIDENT_CHANCE
		var chief := state.chief_of(tribe)
		if chief != -1 and (People.has_trait(state, chief, "fierce") or People.has_trait(state, chief, "proud")):
			chance += 0.1
		if not state.rng.chance(chance):
			continue
		var others: Array[String] = []
		for other: String in state.tribe_names:
			if other != tribe and state.relation(tribe, other) <= 40:
				others.append(other)
		if others.is_empty():
			continue
		var pair := PackedStringArray([tribe, others[state.rng.pick_index(others.size())]])
		var first := state.people_of(pair[0]).filter(func(p: int) -> bool: return People.is_adult(state, p))
		var second := state.people_of(pair[1]).filter(func(p: int) -> bool: return People.is_adult(state, p))
		if first.is_empty() or second.is_empty():
			continue
		var a: int = first[state.rng.pick_index(first.size())]
		var b: int = second[state.rng.pick_index(second.size())]
		var what := INCIDENTS[state.rng.pick_index(INCIDENTS.size())]
		if what == "trampled fields" and state.count_buildings(pair[0], "field") + state.count_buildings(pair[1], "field") == 0:
			what = INCIDENTS[0]
		var anger := -state.rng.randi_range(12, 25)
		state.change_relation(pair[0], pair[1], anger)
		state.change_bond(state.person_ids[a], state.person_ids[b], -40)
		state.log_event("incident", {"tribe": pair[0], "other": pair[1], "what": what,
			"a": state.person_ids[a], "a_name": state.person_names[a], "b": state.person_ids[b], "b_name": state.person_names[b]})
		state.life(state.person_ids[a], "Fell out with %s of the %s over %s." % [state.person_names[b], pair[1], what], "conflict")
		state.life(state.person_ids[b], "Fell out with %s of the %s over %s." % [state.person_names[a], pair[0], what], "conflict")


## A starving tribe may raid the stores of a well-fed neighbor it doesn't count as a friend.
func _raids(state: WorldState) -> void:
	for t: int in state.tribe_count():
		var raider := state.tribe_names[t]
		var population := maxf(state.tribe_population[t], 1.0)
		if state.tribe_food[t] / population > RAID_HUNGRY_DAYS or state.tribe_hungry_days[t] == 0:
			continue
		var victim := -1
		for other: int in state.tribe_count():
			if other == t or state.relation(raider, state.tribe_names[other]) >= 30:
				continue
			if victim == -1 or state.tribe_food[other] > state.tribe_food[victim]:
				victim = other
		if victim == -1 or state.tribe_food[victim] / maxf(state.tribe_population[victim], 1.0) < 45.0:
			continue
		var chance := RAID_CHANCE
		var chief := state.chief_of(raider)
		if chief != -1 and (People.has_trait(state, chief, "fierce") or People.has_trait(state, chief, "greedy")):
			chance *= 2.0
		elif chief != -1 and People.has_trait(state, chief, "kind"):
			chance *= 0.4
		if not state.rng.chance(chance):
			continue
		var taken := state.tribe_food[victim] * RAID_TAKES
		state.tribe_food[victim] -= taken
		state.tribe_food[t] += taken
		state.change_relation(raider, state.tribe_names[victim], RAID_ANGER)
		var data := {"tribe": raider, "victim": state.tribe_names[victim], "days": roundi(taken / population)}
		if chief != -1:
			data["id"] = state.person_ids[chief]
			data["chief"] = state.person_names[chief]
			state.life(state.person_ids[chief], "Led a raid on the stores of the %s." % state.tribe_names[victim], "conflict")
		state.log_event("raid", data)


func _marriages_between(state: WorldState, a: String, b: String) -> int:
	var count := 0
	for p: int in state.person_ids.size():
		if state.person_tribes[p] != a:
			continue
		for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
			var q := state.index_of(parent)
			if q != -1 and state.person_tribes[q] == b:
				count += 1
	return count


## Pairs whose relation is at or below `limit` (or at or above it when `above`), as name pairs,
## so tribes vanishing mid-loop can't shift the indexes under us.
func _pairs(state: WorldState, limit: int, above: bool) -> Array[PackedStringArray]:
	var pairs: Array[PackedStringArray] = []
	for i: int in state.tribe_count():
		for j: int in range(i + 1, state.tribe_count()):
			var value := state.relation(state.tribe_names[i], state.tribe_names[j])
			if (value >= limit) if above else (value <= limit):
				pairs.append(PackedStringArray([state.tribe_names[i], state.tribe_names[j]]))
	return pairs


## Who takes up spears: the strong and the brave of fighting age.
func _fighters(state: WorldState, tribe: String) -> Array[int]:
	var found: Array[int] = []
	for p: int in state.people_of(tribe):
		var years := People.age(state, p)
		if years >= FIGHTING_AGE[0] and years <= FIGHTING_AGE[1] and state.person_due[p] == -1 and state.person_sick[p] == 0:
			found.append(p)
	return found


func _strength(state: WorldState, fighters: Array[int], tribe: String) -> float:
	var total := 0.0
	for p: int in fighters:
		total += 0.6 + Genetics.express(state.person_genomes[p], "strength") + state.person_skills[p][Jobs.SKILLS.find("hunting")] / 100.0
		total += state.person_skills[p][Jobs.SKILLS.find("arms")] / 50.0 + (0.6 if state.person_jobs[p] == "guard" else 0.0)
		if People.has_trait(state, p, "brave"):
			total += 0.3
	var t := state.tribe_index(tribe)
	total *= People.chief_effect(state, tribe, "war") * state.tech_bonus(t, "war") * Society.effect(state, t, "war")
	if state.count_buildings(tribe, "stone_wall") > 0:
		total *= 1.6
	elif state.count_buildings(tribe, "palisade") > 0:
		total *= 1.4
	return total * (0.75 + 0.5 * state.rng.randf())


func _wars(state: WorldState) -> void:
	for pair: PackedStringArray in _pairs(state, WAR_AT, false):
		var i := state.tribe_index(pair[0])
		var j := state.tribe_index(pair[1])
		if i == -1 or j == -1 or not state.rng.chance(WAR_CHANCE):
			continue
		if state.tribe_overlord[i] == pair[1] or state.tribe_overlord[j] == pair[0]:
			continue # a vassal's war with its overlord is a revolt (see _vassals)
		var fighters := {pair[0]: _fighters(state, pair[0]), pair[1]: _fighters(state, pair[1])}
		var strength_a := _strength(state, fighters[pair[0]], pair[0])
		var strength_b := _strength(state, fighters[pair[1]], pair[1])
		var winner := pair[0] if strength_a >= strength_b else pair[1]
		var loser := pair[1] if winner == pair[0] else pair[0]
		var ratio := maxf(strength_a, strength_b) / maxf(minf(strength_a, strength_b), 0.01)
		var fallen: Array[String] = []
		for side: Array in [[loser, winner, LOSER_FALLEN], [winner, loser, WINNER_FALLEN]]:
			var side_fighters: Array[int] = fighters[side[0]]
			var ids: Array[int] = []
			for p: int in side_fighters:
				ids.append(state.person_ids[p])
				state.life(state.person_ids[p], "Fought in the war against the %s." % side[1], "conflict")
			var deaths := mini(ceili(ids.size() * float(side[2])), ids.size()) if side[0] == loser else roundi(ids.size() * float(side[2]))
			for k: int in deaths:
				var pick := state.rng.pick_index(ids.size())
				var p := state.index_of(ids[pick])
				ids.remove_at(pick)
				if p != -1:
					fallen.append(state.person_names[p])
					state.kill_person(p, "war", {"enemy": side[1]})
		var w := state.tribe_index(winner)
		var l := state.tribe_index(loser)
		if w != -1 and l != -1:
			var plunder := minf(state.tribe_food[l], state.tribe_population[l] * WAR_PLUNDER_DAYS)
			state.tribe_food[l] -= plunder
			state.tribe_food[w] += plunder
		state.change_relation(pair[0], pair[1], WAR_EXHAUSTION)
		state.log_event("war", {"winner": winner, "loser": loser, "tribe": loser, "deaths": fallen.size(), "fallen": ", ".join(fallen.slice(0, 5))})
		_maybe_subjugate(state, winner, loser, ratio)


## A decisive winner from the Age of Bronze on, led by an ambitious ruler or a tribe that believes in
## ranks, makes the loser its vassal.
func _maybe_subjugate(state: WorldState, winner: String, loser: String, ratio: float) -> void:
	var w := state.tribe_index(winner)
	var l := state.tribe_index(loser)
	if w == -1 or l == -1 or ratio < VASSAL_AT or state.age_of(w) < 1:
		return
	if state.tribe_overlord[w] or state.tribe_overlord[l] or not Society.vassals_of(state, loser).is_empty():
		return
	var chief := state.chief_of(winner)
	var ambitious := chief != -1 and (People.has_trait(state, chief, "proud") or People.has_trait(state, chief, "greedy") or People.has_trait(state, chief, "fierce"))
	if not ambitious and int(state.tribe_culture[w].get("hierarchy", 0)) < 10:
		return
	state.tribe_overlord[l] = winner
	state.tribe_vassal_since[l] = state.tick
	state.log_event("vassal", {"tribe": loser, "overlord": winner})


## Bitter vassals rise up when they think they can win; loyal old vassals are absorbed.
func _vassals(state: WorldState) -> void:
	for t: int in range(state.tribe_count() - 1, -1, -1):
		if t >= state.tribe_count():
			continue
		var lord := state.tribe_index(state.tribe_overlord[t])
		if lord == -1:
			continue
		var vassal := state.tribe_names[t]
		var overlord := state.tribe_names[lord]
		var feeling := state.relation(vassal, overlord)
		if feeling <= REVOLT_AT and state.rng.chance(0.3):
			var strength_v := _strength(state, _fighters(state, vassal), vassal)
			var strength_o := _strength(state, _fighters(state, overlord), overlord)
			if strength_v >= strength_o * 0.7:
				var won := strength_v >= strength_o
				state.log_event("vassal_revolt", {"tribe": vassal, "overlord": overlord, "won": 1 if won else 0})
				if won:
					state.tribe_overlord[t] = ""
					state.tribe_vassal_since[t] = -1
					state.change_relation(vassal, overlord, 20)
				else:
					state.change_relation(vassal, overlord, 25)
					state.tribe_fear[t] = mini(state.tribe_fear[t] + 15, 100)
				continue
		@warning_ignore("integer_division")
		var years := (state.tick - state.tribe_vassal_since[t]) / WorldState.DAYS_PER_YEAR
		if years >= ANNEX_YEARS and feeling >= 20 and state.tribe_population[t] * 2 <= state.tribe_population[lord] and state.rng.chance(0.25):
			state.log_event("annexed", {"tribe": overlord, "from": vassal, "people": state.tribe_population[t]})
			merge_into(state, t, lord)


## A kind or wise chief tries to mend a feud with a gift of food.
func _gifts(state: WorldState) -> void:
	for t: int in state.tribe_count():
		var tribe := state.tribe_names[t]
		var chief := state.chief_of(tribe)
		if chief == -1 or not (People.has_trait(state, chief, "kind") or People.has_trait(state, chief, "wise")):
			continue
		for other: String in state.tribe_names:
			var value := state.relation(tribe, other)
			if other == tribe or value > -20 or value < -70 or state.tribe_food[t] < state.tribe_population[t] * 60.0:
				continue
			if not state.rng.chance(0.3):
				continue
			var gift := state.tribe_food[t] * 0.12
			state.tribe_food[t] -= gift
			state.tribe_food[state.tribe_index(other)] += gift
			state.change_relation(tribe, other, 15)
			state.log_event("gifts", {"from": tribe, "to": other, "tribe": tribe, "chief": state.person_names[chief], "id": state.person_ids[chief]})
			state.life(state.person_ids[chief], "Sent gifts of food to the %s to make peace." % other, "chief")
			break


func _merges(state: WorldState) -> void:
	for pair: PackedStringArray in _pairs(state, MERGE_AT, true):
		var i := state.tribe_index(pair[0])
		var j := state.tribe_index(pair[1])
		if i == -1 or j == -1:
			continue
		var big := i if state.tribe_population[i] >= state.tribe_population[j] else j
		var small := j if big == i else i
		var size := state.tribe_population[small]
		var young := state.tick - state.tribe_founded[small] < MERGE_SETTLED_YEARS * WorldState.DAYS_PER_YEAR
		var small_enough := size <= MERGE_SMALL or (not young and size < 20 and size <= state.tribe_population[big] / 4.0)
		if not small_enough or not state.rng.chance(MERGE_CHANCE):
			continue
		state.log_event("tribes_merged", {"from": state.tribe_names[small], "into": state.tribe_names[big], "people": state.tribe_population[small], "tribe": state.tribe_names[big]})
		merge_into(state, small, big)


## One tribe joins another with everything it has: its people, its stores and what it knows.
static func merge_into(state: WorldState, small: int, big: int) -> void:
	var into := state.tribe_names[big]
	var from := state.tribe_names[small]
	state.tribe_food[big] += state.tribe_food[small]
	state.tribe_wood[big] += state.tribe_wood[small]
	state.tribe_stone[big] += state.tribe_stone[small]
	state.tribe_metal[big] += state.tribe_metal[small]
	state.tribe_treasury[big] += state.tribe_treasury[small]
	var age_before := state.age_of(big)
	for tech: String in state.tribe_knowledge[small]:
		state.learn(big, tech)
	WorkSystem.announce_age(state, big, age_before)
	for p: int in state.people_of(from):
		state.move_person(p, into)
		state.life(state.person_ids[p], "Joined the %s with the rest of the %s." % [into, from], "tribe")
	state.remove_tribe(state.tribe_index(from))
	WorkSystem.settle_homes(state, state.tribe_index(into))


## When a tribe outgrows its land, a restless young adult may lead their family and friends away.
func _splits(state: WorldState) -> void:
	for t: int in range(state.tribe_count() - 1, -1, -1):
		var tribe := state.tribe_names[t]
		var population := state.tribe_population[t]
		var crowded := population >= SPLIT_AT or (population >= 40 and Needs.shelter(state, t) < 0.6)
		if not crowded or not state.has_room_for_tribe() or not state.rng.chance(SPLIT_CHANCE * People.chief_effect(state, tribe, "split") * Society.effect(state, t, "split")):
			continue
		var leader := _restless_leader(state, t)
		if leader == -1:
			continue
		var followers := _followers(state, leader, population)
		if followers.size() < MIN_FOLLOWERS:
			continue
		split_tribe(state, t, followers, leader)


func _restless_leader(state: WorldState, t: int) -> int:
	var tribe := state.tribe_names[t]
	var members := state.people_of(tribe)
	var best := -1
	var best_score := 0.0
	for p: int in members:
		var years := People.age(state, p)
		if years < 20 or years > 42 or state.person_ids[p] == state.tribe_chiefs[t] or state.person_detained[p] > 0:
			continue
		var score := Genetics.express(state.person_genomes[p], "curiosity") * 30.0 + People.standing(state, p, members) * 0.5
		for trait_id: String in People.traits_of(state, p):
			score += {"curious": 20.0, "brave": 10.0, "proud": 8.0, "fierce": 5.0}.get(trait_id, 0.0)
		if score > best_score:
			best = p
			best_score = score
	return best


## The leader's household, then friends and their households, up to half the tribe.
func _followers(state: WorldState, leader: int, population: int) -> Array[int]:
	var tribe := state.person_tribes[leader]
	var chosen := {}
	var leader_id := state.person_ids[leader]
	var queue: Array[int] = [leader]
	var chief := state.tribe_chiefs[state.tribe_index(tribe)]
	# Brothers and sisters first, then friends, then the restless and unhappy.
	for q: int in People.siblings_of(state, leader):
		if People.is_adult(state, q) and state.person_ids[q] != chief:
			queue.append(q)
	for p: int in state.people_of(tribe):
		if state.bond(leader_id, state.person_ids[p]) >= 20 and People.is_adult(state, p) and state.person_ids[p] != chief:
			queue.append(p)
	for p: int in state.people_of(tribe):
		if People.is_adult(state, p) and state.person_mood[p] < 45 and state.person_ids[p] != chief:
			queue.append(p)
	for p: int in queue:
		if chosen.size() >= population * 0.45:
			break
		for q: int in _household(state, p):
			if state.person_detained[q] == 0:
				chosen[q] = true
	var result: Array[int] = []
	for p: int in chosen:
		result.append(p)
	result.sort()
	return result


## Someone, their partner, and their children under 16 in the same tribe.
func _household(state: WorldState, p: int) -> Array[int]:
	var id := state.person_ids[p]
	var partner := state.person_partners[p]
	var found: Array[int] = [p]
	for q: int in state.people_of(state.person_tribes[p]):
		if q == p:
			continue
		var child := (state.person_mothers[q] == id or state.person_fathers[q] == id or (partner != -1 and (state.person_mothers[q] == partner or state.person_fathers[q] == partner))) and People.age(state, q) < People.ADULT_AT
		if state.person_ids[q] == partner or child:
			found.append(q)
	return found


## Some of a tribe leave with their share of the stores and found a new tribe at the water source
## with the most room, carrying their tents. Returns the new tribe's index.
static func split_tribe(state: WorldState, t: int, leaving: Array[int], leader: int = -1) -> int:
	var from := state.tribe_names[t]
	var share := float(leaving.size()) / maxf(state.tribe_population[t], 1.0)
	var new_name := NameGen.tribe_name(state.rng)
	while state.tribe_index(new_name) != -1:
		new_name = NameGen.tribe_name(state.rng)
	var n := state.add_tribe(new_name, state.roomiest_water())
	for field: String in ["tribe_food", "tribe_wood", "tribe_stone"]:
		var stores: PackedFloat64Array = state.get(field)
		var taken := stores[t] * share
		stores[t] -= taken
		stores[n] = taken
		state.set(field, stores)
	state.tribe_tools[n] = state.tribe_tools[t]
	state.tribe_cloth[n] = state.tribe_cloth[t]
	state.tribe_pots[n] = state.tribe_pots[t]
	state.set_knowledge(n, state.tribe_knowledge[t].duplicate())
	state.set_relation(from, new_name, WorldState.KIN_RELATION)
	# They carry their culture with them, but those who leave are seldom those who were happiest.
	var culture: Dictionary = state.tribe_culture[n]
	for axis: String in Society.CULTURE_AXES:
		culture[axis] = clampi(int(state.tribe_culture[t].get(axis, 0)) + state.rng.randi_range(-12, 12), -100, 100)
	culture["openness"] = clampi(int(culture["openness"]) + 5, -100, 100)
	culture["hierarchy"] = clampi(int(culture["hierarchy"]) - 5, -100, 100)
	var ids: Array[int] = []
	for p: int in leaving:
		ids.append(state.person_ids[p])
	for id: int in ids:
		var p := state.index_of(id)
		state.move_person(p, new_name)
		state.life(id, "Left the %s to found the %s." % [from, new_name], "tribe")
	for k: int in ceili(ids.size() / 5.0):
		state.add_building(new_name, "tent", Buildings.free_slot(state, new_name, "tent")).done(state)
	WorkSystem.settle_homes(state, n)
	var data := {"from": from, "to": new_name, "people": ids.size(), "tribe": new_name}
	if leader != -1:
		var leader_id := ids[leaving.find(leader)] if leaving.has(leader) else -1
		var q := state.index_of(leader_id)
		if q != -1:
			data["leader"] = leader_id
			data["leader_name"] = state.person_names[q]
			state.tribe_chiefs[n] = leader_id
			state.life(leader_id, "Led %d people away to found the %s, and became their chief." % [ids.size(), new_name], "chief")
	state.log_event("tribe_split", data)
	for k: int in [t, n]:
		WorkSystem.measure_work(state, k)
	if state.tribe_chiefs[n] == -1:
		People.choose_chief(state, n, "founding")
	return n


## A split the god chose (a dilemma): the most restless young adult leads their people away.
## Falls back to the youngest third of the tribe if nobody has friends enough to follow.
static func split_by_choice(state: WorldState, t: int) -> int:
	var system := RelationsSystem.new()
	var leader := system._restless_leader(state, t)
	var followers := system._followers(state, leader, state.tribe_population[t]) if leader != -1 else ([] as Array[int])
	if followers.size() < MIN_FOLLOWERS:
		followers = state.people_of(state.tribe_names[t])
		followers.sort_custom(func(a: int, b: int) -> bool: return state.person_born[a] > state.person_born[b])
		followers = followers.slice(0, followers.size() / 3)
		followers.sort()
	return split_tribe(state, t, followers, leader if leader in followers else -1)
