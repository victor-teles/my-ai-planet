class_name CrisisSystem
extends SimSystem
## The turning points of a tribe's politics, each a story told over months, that branches on what
## the sim says and who the ruler is. At most one runs in a tribe at a time (state.tribe_crisis).
##
## - protests -> the ruler gives way (a hated law falls), or cracks down (arrests, fear, emergency
##   powers), or waits; anger that keeps rising becomes an uprising -> revolution (the ruler is
##   driven out, the nobles brought down, the darkest laws torn up, and the rebels' leader rules,
##   for better or worse) or the uprising is crushed (the rebels jailed, or fled to found a tribe
##   of their own, and the screws tightened).
## - coup: when the warriors outgrow a ruler nobody believes in, their general takes the seat.
## - capture: when the merchants grow richer than the state, the richest of them buys it.
## - prophet: a holy outsider preaches; persecuted they become a martyr, else their followers split
##   off, or the old priests lose their hold.
## - succession: under hereditary rule, a rival with more standing than the heir contests the seat,
##   and may fight for it or lead their supporters away.
## Monthly, too: where the law allows it, dissidents are arrested; the detained serve their time;
## where exile is the law, troublemakers are driven out once a year.

const PROTEST_AT := 55
const UPRISING_AT := 65
const MAX_ARRESTS := 3 ## per tribe, per month
const FALLEN := 0.04 ## share of each side's fighters lost in an uprising
const MIN_REBELS := 6
const COUP_QUIET := 15 * WorldState.DAYS_PER_YEAR ## the generals don't topple each other every season


func get_id() -> String:
	return "crisis"


func get_interval() -> int:
	return WorldState.DAYS_PER_MONTH


func update(state: WorldState) -> void:
	_serve_time(state)
	for t: int in state.tribe_count():
		if state.tribe_crisis[t].is_empty():
			_maybe_start(state, t)
		else:
			_advance(state, t)
		if t < state.tribe_count() and Society.flag(state, t, "detain"):
			_arrests(state, t)
	if state.month() == 0:
		for t: int in range(state.tribe_count() - 1, -1, -1):
			if Society.flag(state, t, "exile") and not Society.flag(state, t, "detain"):
				_exile_troublemaker(state, t)


# --- Starting -----------------------------------------------------------------------

func _maybe_start(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	if state.tribe_population[t] < SocietySystem.LAW_MIN_POPULATION:
		return
	var unrest := state.tribe_unrest[t]
	var control := Society.control(state, t)
	if unrest >= PROTEST_AT and state.rng.chance((unrest - 50) / 80.0 * (1.0 - control / 140.0) * (1.0 - state.tribe_fear[t] / 150.0)):
		var leader := _rebel_leader(state, t)
		if leader != -1:
			_start(state, t, "protests", "protests", {"leader": state.person_ids[leader]})
			state.log_event("protests", {"tribe": tribe, "id": state.person_ids[leader], "name": state.person_names[leader], "grievance": _grievance(state, t)})
			state.life(state.person_ids[leader], "Spoke out against the rulers of the %s, and the crowd listened." % tribe, "society")
			return
	var ruler := Society.power(state, t, "ruler")
	var warriors := Society.power(state, t, "warriors")
	var settled := SocietySystem.reign_years(state, t) >= 3.0 and state.ticks_since("coup", tribe, COUP_QUIET) > COUP_QUIET
	if settled and warriors >= 45 and warriors >= ruler + 15 and state.tribe_legitimacy[t] < 50 and state.rng.chance(0.04):
		_coup(state, t)
		return
	var merchants := Society.power(state, t, "merchants")
	if settled and state.age_of(t) >= 3 and merchants >= 50 and merchants >= ruler + 15 and merchants >= Society.power(state, t, "council") and state.rng.chance(0.03):
		_capture(state, t)
		return
	if state.tick - state.tribe_ruler_since[t] <= WorldState.DAYS_PER_MONTH and _inherited_lately(state, tribe):
		_maybe_contest(state, t)
		return
	var piety := int(state.tribe_culture[t].get("piety", 0))
	if state.month() == 3 and (piety >= 25 or state.tribe_legitimacy[t] < 35) and state.rng.chance(0.03):
		var prophet := _prophet(state, t)
		if prophet != -1:
			_start(state, t, "prophet", "preaching", {"leader": state.person_ids[prophet]})
			state.log_event("prophet", {"tribe": tribe, "id": state.person_ids[prophet], "name": state.person_names[prophet]})
			state.life(state.person_ids[prophet], "Began to preach a new truth to the %s." % tribe, "society")


func _start(state: WorldState, t: int, type: String, stage: String, data: Dictionary = {}) -> void:
	var crisis := {"type": type, "stage": stage, "since": state.tick}
	crisis.merge(data)
	state.tribe_crisis[t] = crisis


func _end(state: WorldState, t: int) -> void:
	state.tribe_crisis[t] = {}


func _months_in(state: WorldState, crisis: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(crisis["since"])) / WorldState.DAYS_PER_MONTH


## What people are angriest about, in a few words, for the feed.
func _grievance(state: WorldState, t: int) -> String:
	if state.tribe_hungry_days[t] > 3:
		return "hunger"
	if Society.inequality(state, t) >= 55:
		return "the wealth of the few"
	if Society.count_where(state, t, "detained") >= 2:
		return "the arrests"
	if Society.count_where(state, t, "bonded") >= 3:
		return "bondage"
	var worst := ""
	var worst_fit := 0.0
	for law: String in Society.laws_of(state, t):
		var fit := SocietySystem.fit(state, t, law)
		if fit < worst_fit:
			worst = law
			worst_fit = fit
	if worst:
		return Laws.name_of(worst).to_lower()
	return "their rulers"


# --- Advancing ----------------------------------------------------------------------

func _advance(state: WorldState, t: int) -> void:
	var crisis: Dictionary = state.tribe_crisis[t]
	match String(crisis["type"]):
		"protests":
			_protests(state, t, crisis)
		"prophet":
			_preaching(state, t, crisis)
		"succession":
			_contest(state, t, crisis)
		_:
			_end(state, t)


## The ruler meets the crowd. Gentle rulers and strong councils give way; hard rulers with guards
## crack down; the rest wait, and anger that keeps rising boils over.
func _protests(state: WorldState, t: int, crisis: Dictionary) -> void:
	var tribe := state.tribe_names[t]
	var months := _months_in(state, crisis)
	if String(crisis["stage"]) == "tense":
		if state.tribe_unrest[t] >= UPRISING_AT:
			_uprising(state, t, crisis)
		elif months >= 6:
			_end(state, t)
		return
	if state.tribe_unrest[t] < PROTEST_AT - 15:
		state.log_event("protests_faded", {"tribe": tribe})
		_end(state, t)
		return
	var ruler := state.chief_of(tribe)
	var gentle := ruler != -1 and (People.has_trait(state, ruler, "kind") or People.has_trait(state, ruler, "wise"))
	var harsh := ruler != -1 and (People.has_trait(state, ruler, "fierce") or People.has_trait(state, ruler, "proud") or People.has_trait(state, ruler, "greedy"))
	if (gentle and not harsh) or Society.top_faction(state, t) == "council" or state.tribe_legitimacy[t] >= 60:
		_concede(state, t)
		return
	if harsh or Society.control(state, t) >= 30:
		_crack_down(state, t, crisis)
		return
	if months >= 3 and state.tribe_unrest[t] >= UPRISING_AT:
		_uprising(state, t, crisis)


func _concede(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var worst := ""
	var worst_score := INF
	for law: String in Society.laws_of(state, t):
		var score := SocietySystem.fit(state, t, law) + float(Laws.LAWS[law]["freedom"]) / 10.0
		if score < worst_score:
			worst = law
			worst_score = score
	var data := {"tribe": tribe}
	var ruler := state.chief_of(tribe)
	if ruler != -1:
		data["id"] = state.person_ids[ruler]
		data["name"] = state.person_names[ruler]
	if worst and worst_score < 0.5:
		data["law"] = worst
		state.log_event("concession", data)
		SocietySystem.repeal(state, t, worst, "the people demanded it")
	else:
		# Nothing to strike down: the stores are opened instead.
		if "shared_stores" in SocietySystem.available(state, t):
			SocietySystem.enact(state, t, "shared_stores", "the people demanded it")
		state.log_event("concession", data)
	state.tribe_unrest[t] = maxi(state.tribe_unrest[t] - 30, 0)
	state.tribe_legitimacy[t] = mini(state.tribe_legitimacy[t] + 5, 100)
	_shift_power(state, t, "ruler", -8)
	_end(state, t)


func _crack_down(state: WorldState, t: int, crisis: Dictionary) -> void:
	var tribe := state.tribe_names[t]
	var taken: Array[String] = []
	var leader := state.index_of(int(crisis.get("leader", -1)))
	if Society.flag(state, t, "detain") or Society.control(state, t) >= 30:
		var targets := _dissidents(state, t)
		if leader != -1 and leader not in targets:
			targets.push_front(leader)
		for p: int in targets.slice(0, 3 + targets.size() / 5):
			_detain(state, p, state.rng.randi_range(12, 48), "for protesting")
			taken.append(state.person_names[p])
	elif leader != -1:
		taken.append(state.person_names[leader])
		_banish(state, leader, "for leading the protests")
	state.tribe_fear[t] = mini(state.tribe_fear[t] + 15, 100)
	state.tribe_unrest[t] = maxi(state.tribe_unrest[t] - 15, 0)
	state.tribe_legitimacy[t] = maxi(state.tribe_legitimacy[t] - 8, 0)
	var data := {"tribe": tribe, "count": taken.size(), "names": EconomySystem._names(taken)}
	var ruler := state.chief_of(tribe)
	if ruler != -1:
		data["id"] = state.person_ids[ruler]
		data["name"] = state.person_names[ruler]
	state.log_event("crackdown", data)
	if "emergency_powers" in SocietySystem.available(state, t):
		SocietySystem.enact(state, t, "emergency_powers", "to restore order")
	crisis["stage"] = "tense"
	crisis["since"] = state.tick


## The angry take to the streets against the guards, the nobles and the loyal.
func _uprising(state: WorldState, t: int, crisis: Dictionary) -> void:
	var tribe := state.tribe_names[t]
	var rebels: Array[int] = []
	var loyalists: Array[int] = []
	var ruler_id := state.tribe_chiefs[t]
	for p: int in Society.adults_of(state, t):
		if state.person_detained[p] > 0 or People.age(state, p) > 60:
			continue
		var loyal := state.person_jobs[p] == "guard" or state.person_status[p] == "noble" or state.person_ids[p] == ruler_id or state.person_loyalty[p] >= 65
		if loyal:
			loyalists.append(p)
		elif state.person_loyalty[p] < 35:
			rebels.append(p)
	var leader := state.index_of(int(crisis.get("leader", -1)))
	if leader == -1 or leader not in rebels:
		leader = _rebel_leader(state, t)
	if rebels.size() < MIN_REBELS or leader == -1:
		_end(state, t)
		return
	var rebel_strength := 0.0
	for p: int in rebels:
		rebel_strength += 1.0 + (0.4 if People.has_trait(state, p, "brave") or People.has_trait(state, p, "fierce") else 0.0)
	var loyal_strength := 0.0
	for p: int in loyalists:
		loyal_strength += 2.5 if state.person_jobs[p] == "guard" else (1.5 if state.person_status[p] == "noble" else 0.8)
	loyal_strength *= (1.0 + Society.control(state, t) / 100.0) * state.tech_bonus(t, "war")
	rebel_strength *= 0.75 + 0.5 * state.rng.randf()
	loyal_strength *= 0.75 + 0.5 * state.rng.randf()
	# People die in the fighting, so everyone is held by id from here on.
	var leader_id := state.person_ids[leader]
	var rebel_ids := _ids(state, rebels)
	var loyal_ids := _ids(state, loyalists)
	var fallen := _casualties(state, rebel_ids, "the uprising") + _casualties(state, loyal_ids, "the uprising")
	var leader_now := state.index_of(leader_id)
	if leader_now == -1:
		leader_now = _rebel_leader(state, t)
	if rebel_strength > loyal_strength and leader_now != -1:
		_revolution(state, t, leader_now, fallen)
	else:
		_crushed(state, t, rebel_ids, leader_id, fallen)
	t = state.tribe_index(tribe)
	if t != -1:
		_end(state, t)


func _ids(state: WorldState, people: Array[int]) -> Array[int]:
	var ids: Array[int] = []
	for p: int in people:
		ids.append(state.person_ids[p])
	return ids


## A share of fighters fall. Returns the names of the dead.
func _casualties(state: WorldState, side_ids: Array[int], cause: String) -> Array[String]:
	var ids := side_ids.duplicate()
	var dead: Array[String] = []
	for k: int in roundi(ids.size() * FALLEN):
		var pick := state.rng.pick_index(ids.size())
		var p := state.index_of(ids[pick])
		ids.remove_at(pick)
		if p != -1:
			dead.append(state.person_names[p])
			state.kill_person(p, cause)
	return dead


## The ruler falls. The rebels' leader takes the seat, the nobles are brought down, the treasury is
## shared out and the darkest laws are torn up. What the new ruler does next is up to who they are.
func _revolution(state: WorldState, t: int, leader: int, fallen: Array[String]) -> void:
	var tribe := state.tribe_names[t]
	var old := state.chief_of(tribe)
	var data := {"tribe": tribe, "leader": state.person_ids[leader], "leader_name": state.person_names[leader], "deaths": fallen.size()}
	if old != -1:
		data["old"] = state.person_names[old]
		data["old_id"] = state.person_ids[old]
	var leader_id := state.person_ids[leader]
	if old != -1:
		_banish(state, old, "overthrown")
	leader = state.index_of(leader_id)
	t = state.tribe_index(tribe)
	if leader == -1 or t == -1:
		return
	for p: int in state.people_of(tribe):
		state.person_status[p] = ""
		state.person_detained[p] = 0
	var adults := Society.adults_of(state, t)
	for p: int in adults:
		state.person_wealth[p] += roundi(state.tribe_treasury[t] / maxf(adults.size(), 1.0))
	state.tribe_treasury[t] = 0.0
	state.tribe_dynasty[t] = ""
	for law: String in Society.laws_of(state, t):
		if Laws.is_dystopian(law) or law == "hereditary_rule" or (int(Laws.LAWS[law]["freedom"]) < 0 and state.rng.chance(0.6)):
			state.drop_law(t, law)
	state.tribe_chiefs[t] = leader_id
	state.log_event("revolution", data)
	state.life(leader_id, "Led the revolution of the %s, and took their seat." % tribe, "chief")
	var culture: Dictionary = state.tribe_culture[t]
	culture["hierarchy"] = clampi(int(culture.get("hierarchy", 0)) - 15, -100, 100)
	culture["openness"] = clampi(int(culture.get("openness", 0)) + 8, -100, 100)
	var powers: Dictionary = state.tribe_power[t]
	powers["ruler"] = 15
	powers["council"] = mini(int(powers.get("council", 0)) + 25, 100)
	if People.has_trait(state, leader, "fierce") or People.has_trait(state, leader, "brave"):
		powers["warriors"] = mini(int(powers.get("warriors", 0)) + 15, 100)
	state.tribe_legitimacy[t] = 70
	state.tribe_unrest[t] = 10
	state.tribe_fear[t] = maxi(state.tribe_fear[t] - 20, 0)
	for p: int in adults:
		state.person_loyalty[p] = maxi(state.person_loyalty[p], 55)


## The uprising fails. Its leaders are jailed or driven out; if enough rebels are left standing they
## flee to found a tribe of their own. The rulers tighten their grip.
func _crushed(state: WorldState, t: int, rebel_ids: Array[int], leader_id: int, fallen: Array[String]) -> void:
	var tribe := state.tribe_names[t]
	var data := {"tribe": tribe, "deaths": fallen.size()}
	var leader := state.index_of(leader_id)
	if leader != -1:
		data["leader"] = leader_id
		data["leader_name"] = state.person_names[leader]
	var survivors: Array[int] = []
	for id: int in rebel_ids:
		var p := state.index_of(id)
		if p != -1 and state.person_tribes[p] == tribe:
			survivors.append(p)
	state.log_event("uprising_crushed", data)
	if survivors.size() >= RelationsSystem.MIN_FOLLOWERS and state.has_room_for_tribe() and state.rng.chance(0.5):
		var leaving: Array[int] = []
		for p: int in survivors:
			for q: int in _household(state, p):
				if q not in leaving:
					leaving.append(q)
		leaving.sort()
		var rebel_leader := leader if leader in leaving else -1
		var n := RelationsSystem.split_tribe(state, t, leaving, rebel_leader)
		state.log_event("rebels_fled", {"tribe": state.tribe_names[n], "from": tribe, "people": leaving.size()})
		state.set_relation(tribe, state.tribe_names[n], -25)
		state.tribe_culture[n]["hierarchy"] = clampi(int(state.tribe_culture[n].get("hierarchy", 0)) - 25, -100, 100)
		t = state.tribe_index(tribe)
	else:
		for p: int in survivors.slice(0, 3 + survivors.size() / 3):
			_detain(state, p, state.rng.randi_range(24, 96), "for rising up")
	if t == -1:
		return
	state.tribe_fear[t] = mini(state.tribe_fear[t] + 30, 100)
	state.tribe_unrest[t] = 15
	state.tribe_legitimacy[t] = maxi(state.tribe_legitimacy[t] - 10, 0)
	for law: String in ["secret_police", "emergency_powers"]:
		if law in SocietySystem.available(state, t):
			SocietySystem.enact(state, t, law, "after the uprising")
			break


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


## The general takes the seat.
func _coup(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var members := state.people_of(tribe)
	var general := -1
	var best := -INF
	for p: int in members:
		if not People.is_adult(state, p) or state.person_ids[p] == state.tribe_chiefs[t] or state.person_detained[p] > 0:
			continue
		var score := People.claim(state, p, members, "warriors")
		if score > best:
			general = p
			best = score
	if general == -1:
		return
	var general_id := state.person_ids[general]
	var old := state.chief_of(tribe)
	var data := {"tribe": tribe, "id": general_id, "name": state.person_names[general]}
	if old != -1:
		data["old"] = state.person_names[old]
		_banish(state, old, "deposed by the army")
	t = state.tribe_index(tribe)
	if t == -1 or state.index_of(general_id) == -1:
		return
	state.tribe_chiefs[t] = general_id
	state.tribe_dynasty[t] = ""
	state.log_event("coup", data)
	state.life(general_id, "Seized power over the %s at the head of the warriors." % tribe, "chief")
	var powers: Dictionary = state.tribe_power[t]
	powers["ruler"] = 25
	powers["warriors"] = mini(int(powers.get("warriors", 0)) + 15, 100)
	state.tribe_fear[t] = mini(state.tribe_fear[t] + 15, 100)
	for law: String in ["emergency_powers", "standing_army", "warrior_band"]:
		if law in SocietySystem.available(state, t):
			SocietySystem.enact(state, t, law, "by order of the army")
			break


## The richest merchant buys the state.
func _capture(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var richest := -1
	for p: int in state.people_of(tribe):
		if state.person_jobs[p] == "merchant" and (richest == -1 or state.person_wealth[p] > state.person_wealth[richest]):
			richest = p
	if richest == -1 or state.person_ids[richest] == state.tribe_chiefs[t]:
		return
	var old := state.chief_of(tribe)
	var data := {"tribe": tribe, "id": state.person_ids[richest], "name": state.person_names[richest]}
	if old != -1:
		data["old"] = state.person_names[old]
		state.life(state.person_ids[old], "Was bought out of power by %s." % state.person_names[richest], "chief")
	state.tribe_chiefs[t] = state.person_ids[richest]
	state.tribe_dynasty[t] = ""
	state.log_event("capture", data)
	state.life(state.person_ids[richest], "Bought the seat of power over the %s." % tribe, "chief")
	for law: String in ["corporate_charter", "factory_discipline", "taxation"]:
		if law in SocietySystem.available(state, t):
			SocietySystem.enact(state, t, law, "for the good of business")
			break


## A prophet preaches. A state faith (or rule by priests) persecutes them, and a martyr is made;
## otherwise their following grows until it leaves or the old priests give way.
func _preaching(state: WorldState, t: int, crisis: Dictionary) -> void:
	var tribe := state.tribe_names[t]
	var prophet := state.index_of(int(crisis["leader"]))
	if prophet == -1 or state.person_tribes[prophet] != tribe:
		_end(state, t)
		return
	var months := _months_in(state, crisis)
	if Society.has_law(state, t, "state_religion") or (Society.top_faction(state, t) == "priests" and Society.flag(state, t, "detain")):
		_detain(state, prophet, 120, "for heresy")
		state.log_event("prophet_silenced", {"tribe": tribe, "id": state.person_ids[prophet], "name": state.person_names[prophet]})
		state.tribe_unrest[t] = mini(state.tribe_unrest[t] + 10, 100)
		state.tribe_culture[t]["piety"] = clampi(int(state.tribe_culture[t].get("piety", 0)) + 5, -100, 100)
		_end(state, t)
		return
	if months < 6:
		return
	var followers: Array[int] = []
	for p: int in Society.adults_of(state, t):
		if p != prophet and state.person_ids[p] != state.tribe_chiefs[t] and (state.bond(state.person_ids[p], state.person_ids[prophet]) >= 20 or (People.has_trait(state, p, "devout") and state.person_loyalty[p] < 50) or state.person_loyalty[p] < 30):
			followers.append(p)
	if followers.size() + 1 >= RelationsSystem.MIN_FOLLOWERS and state.tribe_population[t] >= 30 and state.has_room_for_tribe() and state.rng.chance(0.6):
		var leaving: Array[int] = []
		for p: int in [prophet] + followers:
			for q: int in _household(state, p):
				if q not in leaving:
					leaving.append(q)
		leaving.sort()
		var prophet_name := state.person_names[prophet]
		var n := RelationsSystem.split_tribe(state, t, leaving, prophet)
		state.log_event("schism", {"tribe": state.tribe_names[n], "from": tribe, "id": int(crisis["leader"]), "name": prophet_name, "people": leaving.size()})
		state.tribe_culture[n]["piety"] = clampi(int(state.tribe_culture[n].get("piety", 0)) + 25, -100, 100)
		state.set_relation(tribe, state.tribe_names[n], -10)
		t = state.tribe_index(tribe)
	else:
		state.log_event("reform", {"tribe": tribe, "id": state.person_ids[prophet], "name": state.person_names[prophet]})
		_shift_power(state, t, "priests", -15)
		state.change_bond(state.person_ids[prophet], state.tribe_chiefs[t], 10)
	if t != -1:
		_end(state, t)


## Under hereditary rule, a rival with more standing than the heir may contest the seat.
func _maybe_contest(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var heir := state.chief_of(tribe)
	if heir == -1:
		return
	var members := state.people_of(tribe)
	var heir_claim := People.standing(state, heir, members)
	var rival := -1
	var rival_claim := heir_claim + 15.0
	for p: int in members:
		if p == heir or not People.is_adult(state, p) or People.age(state, p) < 20 or state.person_detained[p] > 0:
			continue
		var kin := state.person_families[p] == state.person_families[heir]
		var ambitious := People.has_trait(state, p, "proud") or People.has_trait(state, p, "fierce") or People.has_trait(state, p, "greedy")
		if not kin and not ambitious:
			continue
		var score := People.standing(state, p, members)
		if score > rival_claim:
			rival = p
			rival_claim = score
	if rival == -1:
		return
	_start(state, t, "succession", "contested", {"heir": state.person_ids[heir], "rival": state.person_ids[rival]})
	state.log_event("succession_contested", {"tribe": tribe, "id": state.person_ids[rival], "name": state.person_names[rival], "heir": state.person_names[heir]})
	state.life(state.person_ids[rival], "Claimed the seat of the %s from %s." % [tribe, state.person_names[heir]], "chief")


func _contest(state: WorldState, t: int, crisis: Dictionary) -> void:
	var tribe := state.tribe_names[t]
	var heir := state.index_of(int(crisis["heir"]))
	var rival := state.index_of(int(crisis["rival"]))
	if heir == -1 or rival == -1 or state.person_tribes[rival] != tribe or state.tribe_chiefs[t] != int(crisis["heir"]):
		_end(state, t)
		return
	if not state.rng.chance(0.3):
		return
	var for_heir: Array[int] = []
	var for_rival: Array[int] = []
	for p: int in Society.adults_of(state, t):
		if p == heir or p == rival:
			continue
		var lean := state.bond(state.person_ids[p], state.person_ids[rival]) - state.bond(state.person_ids[p], state.person_ids[heir])
		if lean > 10:
			for_rival.append(p)
		elif lean < -10 or state.person_status[p] == "noble":
			for_heir.append(p)
	if for_rival.size() < 4 or state.rng.chance(0.4):
		state.log_event("succession_settled", {"tribe": tribe, "id": state.person_ids[heir], "name": state.person_names[heir], "rival": state.person_names[rival]})
		state.change_bond(state.person_ids[heir], state.person_ids[rival], -30)
		_end(state, t)
		return
	# The rival leads their supporters away rather than spill kin blood, if there are enough of them.
	if for_rival.size() + 1 >= RelationsSystem.MIN_FOLLOWERS and state.has_room_for_tribe():
		var leaving: Array[int] = []
		for p: int in [rival] + for_rival:
			for q: int in _household(state, p):
				if q not in leaving:
					leaving.append(q)
		leaving.sort()
		var rival_name := state.person_names[rival]
		var n := RelationsSystem.split_tribe(state, t, leaving, rival)
		state.log_event("succession_split", {"tribe": state.tribe_names[n], "from": tribe, "name": rival_name, "people": leaving.size()})
		state.set_relation(tribe, state.tribe_names[n], -25)
		t = state.tribe_index(tribe)
	else:
		var heir_side: Array[int] = [heir]
		heir_side.append_array(for_heir)
		var rival_side: Array[int] = [rival]
		rival_side.append_array(for_rival)
		var heir_ids := _ids(state, heir_side)
		var rival_ids := _ids(state, rival_side)
		var fallen := _casualties(state, heir_ids, "the succession war") + _casualties(state, rival_ids, "the succession war")
		var rival_alive := state.index_of(int(crisis["rival"]))
		var heir_alive := state.index_of(int(crisis["heir"]))
		var rival_wins := rival_alive != -1 and (heir_alive == -1 or (for_rival.size() > for_heir.size() and state.rng.chance(0.6)))
		if rival_wins:
			state.tribe_chiefs[t] = state.person_ids[rival_alive]
			state.tribe_dynasty[t] = state.person_families[rival_alive]
			state.log_event("succession_war", {"tribe": tribe, "id": state.person_ids[rival_alive], "name": state.person_names[rival_alive], "deaths": fallen.size()})
			if heir_alive != -1:
				_banish(state, heir_alive, "lost the war of succession")
		else:
			state.log_event("succession_war", {"tribe": tribe, "id": int(crisis["heir"]), "name": People.name_of(state, int(crisis["heir"])), "deaths": fallen.size()})
			if rival_alive != -1:
				_banish(state, rival_alive, "lost the war of succession")
		t = state.tribe_index(tribe)
	if t != -1:
		_end(state, t)


func _inherited_lately(state: WorldState, tribe: String) -> bool:
	for j: int in range(state.events.size() - 1, -1, -1):
		var event := state.events[j]
		if state.tick - int(event["tick"]) > WorldState.DAYS_PER_MONTH:
			return false
		if event["type"] == "new_chief" and String(event["data"].get("tribe", "")) == tribe:
			return String(event["data"].get("reason", "")) == "inheritance"
	return false


# --- Arrests, custody, exile --------------------------------------------------------

## Where the law allows it, the watchers take dissidents in; the more they watch, the more they find.
func _arrests(state: WorldState, t: int) -> void:
	var chance := (0.02 + 0.1 * Society.control(state, t) / 100.0) * (1.0 + Society.effect(state, t, "surveillance"))
	var made := 0
	for p: int in _dissidents(state, t):
		if made >= MAX_ARRESTS:
			break
		if state.rng.chance(chance):
			_detain(state, p, state.rng.randi_range(6, 36), _charge(state, t))
			made += 1


func _charge(state: WorldState, t: int) -> String:
	if Society.has_law(state, t, "state_religion"):
		return "for heresy"
	if Society.has_law(state, t, "social_credit"):
		return "for a failing score"
	if Society.has_law(state, t, "surveillance_net"):
		return "for what the cameras saw"
	return "for disloyalty"


static func _detain(state: WorldState, p: int, months: int, why: String) -> void:
	var id := state.person_ids[p]
	state.person_detained[p] = maxi(state.person_detained[p], months)
	state.person_jobs[p] = ""
	var t := state.tribe_index(state.person_tribes[p])
	state.log_event("arrest", {"tribe": state.person_tribes[p], "id": id, "name": state.person_names[p], "why": why, "months": months})
	state.life(id, "Was taken into custody %s." % why, "society")
	if t != -1:
		state.tribe_fear[t] = mini(state.tribe_fear[t] + 2, 100)
	# Their family won't forgive it.
	for q: int in state.person_ids.size():
		var kin := state.person_partners[p] == state.person_ids[q] or state.person_mothers[q] == id or state.person_fathers[q] == id \
			or state.person_mothers[p] == state.person_ids[q] or state.person_fathers[p] == state.person_ids[q]
		if kin:
			state.person_loyalty[q] = maxi(state.person_loyalty[q] - 15, 0)


func _serve_time(state: WorldState) -> void:
	for p: int in state.person_ids.size():
		if state.person_detained[p] <= 0:
			continue
		state.person_detained[p] -= 1
		state.person_health[p] = maxi(state.person_health[p] - 1, 10)
		if state.person_detained[p] == 0:
			state.life(state.person_ids[p], "Was released.", "society")
			state.person_loyalty[p] = mini(state.person_loyalty[p], 20)


## Once a year, where exile is the law, the worst troublemaker is driven out.
func _exile_troublemaker(state: WorldState, t: int) -> void:
	var worst := -1
	var worst_score := 0.0
	for p: int in Society.adults_of(state, t):
		if state.person_ids[p] == state.tribe_chiefs[t]:
			continue
		var score := (Society.DISSENT_AT - state.person_loyalty[p]) * 1.0
		for entry: Dictionary in People.strongest_bonds(state, state.person_ids[p], 6):
			if int(entry["value"]) <= -40:
				score += 8.0
		if score > worst_score + 10.0:
			worst = p
			worst_score = score
	if worst != -1 and state.rng.chance(0.5):
		_banish(state, worst, "for troubling the peace")


## Drives someone out: to a tribe that will have them, or off the island for good.
static func _banish(state: WorldState, p: int, why: String) -> void:
	var tribe := state.person_tribes[p]
	var id := state.person_ids[p]
	var name := state.person_names[p]
	var refuge := ""
	var best := -30
	for other: String in state.tribe_names:
		if other != tribe and state.relation(tribe, other) > best:
			refuge = other
			best = state.relation(tribe, other)
	if refuge:
		state.move_person(p, refuge)
		state.person_status[p] = ""
		state.person_loyalty[p] = 50
		state.log_event("exiled", {"tribe": tribe, "id": id, "name": name, "why": why, "to": refuge})
		state.life(id, "Was driven out of the %s (%s), and taken in by the %s." % [tribe, why, refuge], "society")
		var to := state.tribe_index(refuge)
		if to != -1:
			WorkSystem.settle_homes(state, to)
	else:
		state.log_event("exiled", {"tribe": tribe, "id": id, "name": name, "why": why})
		state.kill_person(p, "exile")


# --- Who stands out -----------------------------------------------------------------

func _dissidents(state: WorldState, t: int) -> Array[int]:
	var found: Array[int] = []
	for p: int in Society.adults_of(state, t):
		if Society.is_dissident(state, p) and state.person_ids[p] != state.tribe_chiefs[t]:
			found.append(p)
	found.sort_custom(func(a: int, b: int) -> bool: return state.person_loyalty[a] < state.person_loyalty[b] or (state.person_loyalty[a] == state.person_loyalty[b] and a < b))
	return found


## The boldest of the disaffected: the one the angry would follow.
func _rebel_leader(state: WorldState, t: int) -> int:
	var members := state.people_of(state.tribe_names[t])
	var best := -1
	var best_score := -INF
	for p: int in members:
		if not People.is_adult(state, p) or state.person_loyalty[p] >= 40 or state.person_detained[p] > 0 or state.person_ids[p] == state.tribe_chiefs[t]:
			continue
		var score := People.standing(state, p, members) - state.person_loyalty[p] * 0.5
		for trait_id: String in People.traits_of(state, p):
			score += {"brave": 12.0, "proud": 8.0, "fierce": 8.0, "curious": 6.0, "kind": 4.0}.get(trait_id, 0.0)
		if score > best_score:
			best = p
			best_score = score
	return best


func _prophet(state: WorldState, t: int) -> int:
	var best := -1
	var best_score := 0.0
	for p: int in Society.adults_of(state, t):
		if state.person_ids[p] == state.tribe_chiefs[t] or state.person_detained[p] > 0 or state.person_jobs[p] == "shaman":
			continue
		var score := 0.0
		if People.has_trait(state, p, "devout"):
			score += 20.0
		if People.has_trait(state, p, "curious"):
			score += 12.0
		score += (50 - state.person_loyalty[p]) * 0.4 + Genetics.express(state.person_genomes[p], "sociability") * 15.0
		if score > best_score:
			best = p
			best_score = score
	return best if best_score >= 25.0 else -1


func _shift_power(state: WorldState, t: int, faction: String, delta: int) -> void:
	var powers: Dictionary = state.tribe_power[t]
	powers[faction] = clampi(int(powers.get(faction, 0)) + delta, 0, 100)
