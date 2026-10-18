class_name SocialSystem
extends SimSystem
## People meet every day: housemates, workmates, anyone around the fire, and now and then
## someone from a tribe that shares their spring. Each meeting warms or sours what they feel for
## each other, depending on how their natures fit. Some pairs have a spark: they fall in love,
## one proposes, and the other says yes or no. Couples share a home and raise children; some
## part ways, and bitter rivals sometimes come to blows.

const MEETINGS_PER_PERSON := 0.14 ## per day
const SPARK_AT := 0.55 ## chemistry above this lets love grow
const IN_LOVE_AT := 35
const PROPOSE_AT := 70
const MAX_AGE_GAP := 12
const CROSS_TRIBE_MEETINGS := 3 ## per month, between tribes that share water or like each other
const SEEK_LOVE := 0.25 ## share of a single adult's meetings spent seeking someone they're drawn to
const GATHERING_MONTH := 6 ## midsummer: the singles of friendly tribes meet at the gathering
const GATHERING_MEETINGS := 4 ## per single adult
const MATCH_AGE := 24 ## singles this old may have a match arranged by their families
const MATCH_CHANCE := 0.04 ## per month
## How two traits get along: positive is friendship, negative friction. Symmetric.
const FIT := {
	"kind|kind": 2, "kind|cheerful": 2, "cheerful|cheerful": 2, "wise|wise": 1, "wise|kind": 1,
	"devout|devout": 1, "brave|brave": 1, "curious|curious": 1, "curious|wise": 1,
	"fierce|kind": -2, "fierce|fierce": -2, "fierce|proud": -2, "proud|proud": -2, "greedy|greedy": -1,
	"greedy|kind": -1, "lazy|proud": -1, "lazy|brave": -1, "fierce|cheerful": -1, "greedy|proud": -1,
}


func get_id() -> String:
	return "social"


func update(state: WorldState) -> void:
	for t: int in state.tribe_count():
		_daily_meetings(state, t)
	if state.is_month_start():
		if state.month() == GATHERING_MONTH:
			_gathering(state)
		_cross_tribe(state)
		_fade(state)
		_proposals(state)
		_arranged_matches(state)
		_separations(state)
		_fights(state)


func _daily_meetings(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var members: Array[int] = []
	var by_home := {}
	var by_job := {}
	for p: int in state.person_ids.size():
		if state.person_tribes[p] != tribe or People.age(state, p) < 4:
			continue
		members.append(p)
		var home := state.person_homes[p]
		if home != -1:
			if not by_home.has(home):
				by_home[home] = []
			(by_home[home] as Array).append(p)
		var job := state.person_jobs[p]
		if job:
			if not by_job.has(job):
				by_job[job] = []
			(by_job[job] as Array).append(p)
	if members.size() < 2:
		return
	var count := state.rng.round_stochastic(members.size() * MEETINGS_PER_PERSON)
	for k: int in count:
		var a := members[state.rng.pick_index(members.size())]
		var roll := state.rng.randf()
		var circle: Array = members
		if roll < 0.4 and by_home.has(state.person_homes[a]):
			circle = by_home[state.person_homes[a]]
		elif roll < 0.7 and by_job.has(state.person_jobs[a]):
			circle = by_job[state.person_jobs[a]]
		var b: int = circle[state.rng.pick_index(circle.size())]
		if state.person_partners[a] == -1 and People.is_adult(state, a) and state.rng.chance(SEEK_LOVE):
			b = _seek(state, a, members)
		if a != b:
			interact(state, a, b)


## Someone single looks for the one they're sweet on, or for anyone they might be.
func _seek(state: WorldState, a: int, members: Array[int]) -> int:
	var id := state.person_ids[a]
	var best := -1
	var best_love := 0
	for b: int in members:
		var love := state.love(id, state.person_ids[b])
		if love > best_love and state.person_partners[b] == -1:
			best = b
			best_love = love
	if best != -1 and state.rng.chance(0.7):
		return best
	for attempt: int in 4:
		var b := members[state.rng.pick_index(members.size())]
		if b != a and _could_court(state, a, b):
			return b
	return a


## Two people spend time together. Returns the change in what they feel for each other.
static func interact(state: WorldState, a: int, b: int) -> int:
	var id_a := state.person_ids[a]
	var id_b := state.person_ids[b]
	var genome_a := state.person_genomes[a]
	var genome_b := state.person_genomes[b]
	var fit := 0
	for trait_a: String in People.traits_of(state, a):
		for trait_b: String in People.traits_of(state, b):
			fit += int(FIT.get("%s|%s" % [trait_a, trait_b] if trait_a <= trait_b else "%s|%s" % [trait_b, trait_a], 0))
	var warmth := Genetics.express(genome_a, "sociability") + Genetics.express(genome_b, "sociability") - 1.0
	var delta := state.rng.randi_range(-2, 4) + fit + roundi(warmth * 2.0)
	var temper := Genetics.express(genome_a, "temper") + Genetics.express(genome_b, "temper")
	var adults := People.is_adult(state, a) and People.is_adult(state, b)
	if adults and state.rng.chance(0.022 * temper + (0.05 if state.person_mood[a] < 30 else 0.0)):
		delta = -state.rng.randi_range(4, 10)
		state.meet(id_a, id_b, "quarrel")
	var value := state.change_bond(id_a, id_b, delta)
	if state.person_partners[a] == id_b:
		state.change_love(id_a, id_b, 1 if delta > 0 else -1)
		if delta > 0:
			state.meet(id_a, id_b, "love")
		return delta
	if delta >= 0 and _could_court(state, a, b):
		var spark := chemistry(state, id_a, id_b)
		if People.are_cousins(state, id_a, id_b):
			spark *= 0.85
		if spark > SPARK_AT and value > 0:
			var before := state.love(id_a, id_b)
			var gain := roundi(2.0 + (spark - SPARK_AT) * 12.0 * (0.5 + _attractive(state, b)))
			var love := state.change_love(id_a, id_b, gain)
			state.meet(id_a, id_b, "flirt")
			if before < IN_LOVE_AT and love >= IN_LOVE_AT:
				state.log_event("romance", {"tribe": state.person_tribes[a], "a": id_a, "a_name": state.person_names[a], "b": id_b, "b_name": state.person_names[b]})
				state.life(id_a, "Fell in love with %s." % state.person_names[b], "love")
				state.life(id_b, "Fell in love with %s." % state.person_names[a], "love")
			return delta
	if delta > 0 and state.rng.chance(0.3):
		state.meet(id_a, id_b, "chat")
	return delta


## 0..1, fixed for a pair: some people simply click.
static func chemistry(state: WorldState, a: int, b: int) -> float:
	return posmod(hash([mini(a, b), maxi(a, b), state.seed_value, "spark"]), 1000) / 1000.0


## How appealing someone is, broadly: health, warmth, vigor and wit.
static func _attractive(state: WorldState, p: int) -> float:
	var genome := state.person_genomes[p]
	return 0.25 * Genetics.express(genome, "vitality") + 0.25 * Genetics.express(genome, "sociability") \
		+ 0.2 * state.person_health[p] / 100.0 + 0.15 * Genetics.express(genome, "strength") + 0.15 * Genetics.express(genome, "intellect")


## Free to fall in love with each other: both grown, unattached, not mourning deeply, drawn to
## each other's sex, close enough in age and not close kin.
static func _could_court(state: WorldState, a: int, b: int) -> bool:
	if state.person_partners[a] != -1 or state.person_partners[b] != -1:
		return false
	var age_a := People.age(state, a)
	var age_b := People.age(state, b)
	if age_a < People.ADULT_AT or age_b < People.ADULT_AT or absi(age_a - age_b) > MAX_AGE_GAP + maxi(mini(age_a, age_b) - 30, 0) / 3:
		return false
	if state.person_grief[a] > 4 or state.person_grief[b] > 4:
		return false
	if state.person_detained[a] > 0 or state.person_detained[b] > 0:
		return false
	# Where nobles must marry nobles, love across the line goes nowhere.
	if (state.person_status[a] == "noble") != (state.person_status[b] == "noble"):
		for p: int in [a, b]:
			if Society.flag(state, state.tribe_index(state.person_tribes[p]), "class_marriage"):
				return false
	if not _drawn_to(state, a, b) or not _drawn_to(state, b, a):
		return false
	return not People.is_close_kin(state, state.person_ids[a], state.person_ids[b])


static func _drawn_to(state: WorldState, a: int, b: int) -> bool:
	var same := state.person_sexes[a] == state.person_sexes[b]
	match state.person_attraction[a]:
		0:
			return not same
		1:
			return same
	return true


func _cross_tribe(state: WorldState) -> void:
	for i: int in state.tribe_count():
		for j: int in range(i + 1, state.tribe_count()):
			var friendly := state.relation(state.tribe_names[i], state.tribe_names[j]) >= 20
			if not friendly and state.tribe_water[i] != state.tribe_water[j]:
				continue
			var first := _adults(state, state.tribe_names[i])
			var second := _adults(state, state.tribe_names[j])
			if first.is_empty() or second.is_empty():
				continue
			for k: int in CROSS_TRIBE_MEETINGS:
				interact(state, first[state.rng.pick_index(first.size())], second[state.rng.pick_index(second.size())])


## Midsummer: the singles of every tribe meet those of their own and of friendly tribes.
func _gathering(state: WorldState) -> void:
	var singles: Array[int] = []
	for p: int in state.person_ids.size():
		if state.person_partners[p] == -1 and People.is_adult(state, p) and People.age(state, p) < 45:
			singles.append(p)
	if singles.size() < 2:
		return
	for a: int in singles:
		for k: int in GATHERING_MEETINGS:
			var b := singles[state.rng.pick_index(singles.size())]
			if b == a:
				continue
			var tribe_a := state.person_tribes[a]
			var tribe_b := state.person_tribes[b]
			if tribe_a != tribe_b and state.relation(tribe_a, tribe_b) < 0:
				continue
			interact(state, a, b)


func _adults(state: WorldState, tribe: String) -> Array[int]:
	var found: Array[int] = []
	for p: int in state.people_of(tribe):
		if People.is_adult(state, p):
			found.append(p)
	return found


## Feelings left alone fade: shallow ones monthly, deep ones every few months. Love that isn't
## a marriage fades faster.
func _fade(state: WorldState) -> void:
	var deep_fades := state.month() % 3 == 0
	for key: String in state.bonds.keys():
		var value := int(state.bonds[key])
		if absi(value) > 60 and not deep_fades:
			continue
		value -= signi(value)
		if value == 0:
			state.bonds.erase(key)
		else:
			state.bonds[key] = value
	for key: String in state.romance.keys():
		var parts := key.split("|")
		var a := state.index_of(parts[0].to_int())
		if a != -1 and state.person_partners[a] == parts[1].to_int():
			continue
		var value := int(state.romance[key]) - 1
		if value <= 0:
			state.romance.erase(key)
		else:
			state.romance[key] = value


## Pairs deep in love: one asks, the other answers. Keys are sorted so the dice fall the same
## way after a save and load.
func _proposals(state: WorldState) -> void:
	var keys: Array[String] = []
	for key: String in state.romance:
		if int(state.romance[key]) >= PROPOSE_AT:
			keys.append(key)
	keys.sort()
	for key: String in keys:
		var parts := key.split("|")
		var a := state.index_of(parts[0].to_int())
		var b := state.index_of(parts[1].to_int())
		if a == -1 or b == -1 or not _could_court(state, a, b):
			continue
		if not state.rng.chance(0.5):
			continue # not this month
		var asker := a if _boldness(state, a) + state.rng.randf() * 0.5 >= _boldness(state, b) + state.rng.randf() * 0.5 else b
		var asked := b if asker == a else a
		var id_asker := state.person_ids[asker]
		var id_asked := state.person_ids[asked]
		var yes := clampf(0.35 + state.bond(id_asker, id_asked) / 150.0 + state.love(id_asker, id_asked) / 200.0, 0.1, 0.95)
		if People.has_trait(state, asked, "proud"):
			yes -= 0.1
		if state.rng.chance(yes):
			marry(state, asker, asked)
		else:
			state.change_love(id_asker, id_asked, -35)
			state.change_bond(id_asker, id_asked, -10)
			state.person_mood[asker] = maxi(state.person_mood[asker] - 20, 0)
			state.log_event("proposal_refused", {"tribe": state.person_tribes[asker], "a": id_asker, "a_name": state.person_names[asker], "b": id_asked, "b_name": state.person_names[asked]})
			state.life(id_asker, "Asked %s to share a hearth, and was turned down." % state.person_names[asked], "love")
			state.life(id_asked, "Turned down %s." % state.person_names[asker], "love")


static func _boldness(state: WorldState, p: int) -> float:
	var bold := Genetics.express(state.person_genomes[p], "sociability")
	for trait_id: String in People.traits_of(state, p):
		bold += {"brave": 0.3, "cheerful": 0.2, "proud": 0.15, "fierce": 0.1}.get(trait_id, 0.0)
	return bold


## Joins two people. If they're from different tribes, one moves to the other's (the one from
## the smaller tribe, usually) and the two tribes warm to each other.
static func marry(state: WorldState, a: int, b: int) -> void:
	var id_a := state.person_ids[a]
	var id_b := state.person_ids[b]
	state.person_partners[a] = id_b
	state.person_partners[b] = id_a
	state.change_bond(id_a, id_b, 20)
	state.change_love(id_a, id_b, 10)
	var data := {"a": id_a, "a_name": state.person_names[a], "b": id_b, "b_name": state.person_names[b]}
	var tribe_a := state.person_tribes[a]
	var tribe_b := state.person_tribes[b]
	var stayer := a
	var mover := b
	if tribe_a != tribe_b:
		var size_a := state.tribe_population[state.tribe_index(tribe_a)]
		var size_b := state.tribe_population[state.tribe_index(tribe_b)]
		if size_a < size_b or (size_a == size_b and state.rng.chance(0.5)):
			stayer = b
			mover = a
		var from := state.person_tribes[mover]
		var to := state.person_tribes[stayer]
		# Their young children come along.
		for q: int in state.person_ids.size():
			if (state.person_mothers[q] == state.person_ids[mover] or state.person_fathers[q] == state.person_ids[mover]) and People.age(state, q) < People.ADULT_AT and state.person_tribes[q] == from:
				state.move_person(q, to)
		state.move_person(mover, to)
		state.change_relation(from, to, 8)
		data.merge({"moved_from": from, "mover": state.person_ids[mover], "mover_name": state.person_names[mover], "stayer_name": state.person_names[stayer]})
		state.life(state.person_ids[mover], "Left the %s to marry %s of the %s." % [from, state.person_names[stayer], to], "love")
		state.life(state.person_ids[stayer], "Married %s of the %s." % [state.person_names[mover], from], "love")
		WorkSystem.measure_work(state, state.tribe_index(from))
	else:
		state.life(id_a, "Married %s." % state.person_names[b], "love")
		state.life(id_b, "Married %s." % state.person_names[a], "love")
	data["tribe"] = state.person_tribes[stayer]
	state.log_event("marriage", data)
	_set_up_home(state, stayer, mover)


## Newlyweds take an empty home if there is one; otherwise one moves in with the other, and the
## tribe will want to build them a place of their own.
static func _set_up_home(state: WorldState, a: int, b: int) -> void:
	var tribe := state.person_tribes[a]
	var used := {}
	for p: int in state.person_ids.size():
		if state.person_homes[p] != -1:
			used[state.person_homes[p]] = true
	var children: Array[int] = []
	for p: int in state.person_ids.size():
		var parent_is_spouse := state.person_mothers[p] in [state.person_ids[a], state.person_ids[b]] or state.person_fathers[p] in [state.person_ids[a], state.person_ids[b]]
		if parent_is_spouse and People.age(state, p) < People.ADULT_AT and state.person_tribes[p] == tribe and state.person_homes[p] == state.person_homes[a]:
			children.append(p)
	for b_index: int in state.buildings_of(tribe):
		var id := state.building_ids[b_index]
		if Buildings.is_home(state.building_types[b_index]) and state.is_built(b_index) and not used.has(id):
			for p: int in [a, b] + children:
				state.person_homes[p] = id
			return
	if state.person_homes[a] != -1:
		state.person_homes[b] = state.person_homes[a]
	elif state.person_homes[b] != -1:
		state.person_homes[a] = state.person_homes[b]


## Families find a match for those still single at MATCH_AGE: someone they could love and don't dislike.
func _arranged_matches(state: WorldState) -> void:
	var ids: Array[int] = []
	for p: int in state.person_ids.size():
		var years := People.age(state, p)
		if state.person_partners[p] == -1 and years >= MATCH_AGE and years < 45:
			ids.append(state.person_ids[p])
	for id: int in ids:
		var a := state.index_of(id)
		if a == -1 or state.person_partners[a] != -1 or not state.rng.chance(MATCH_CHANCE):
			continue
		var best := -1
		var best_score := -INF
		for b: int in state.people_of(state.person_tribes[a]):
			if b == a or not _could_court(state, a, b):
				continue
			var score := state.bond(id, state.person_ids[b]) + state.love(id, state.person_ids[b]) + chemistry(state, id, state.person_ids[b]) * 20.0
			if state.bond(id, state.person_ids[b]) >= -10 and score > best_score:
				best = b
				best_score = score
		if best != -1:
			state.life(id, "The families arranged a match with %s." % state.person_names[best], "love")
			state.life(state.person_ids[best], "The families arranged a match with %s." % state.person_names[a], "love")
			marry(state, a, best)


## A marriage gone sour may end.
func _separations(state: WorldState) -> void:
	for p: int in state.person_ids.size():
		var partner_id := state.person_partners[p]
		if partner_id == -1 or partner_id < state.person_ids[p]:
			continue # each couple once
		var q := state.index_of(partner_id)
		if q == -1 or state.bond(state.person_ids[p], partner_id) > -20 or not state.rng.chance(0.06):
			continue
		state.person_partners[p] = -1
		state.person_partners[q] = -1
		state.change_love(state.person_ids[p], partner_id, -100)
		state.log_event("separation", {"tribe": state.person_tribes[p], "a": state.person_ids[p], "a_name": state.person_names[p], "b": partner_id, "b_name": state.person_names[q]})
		state.life(state.person_ids[p], "Parted ways with %s." % state.person_names[q], "love")
		state.life(partner_id, "Parted ways with %s." % state.person_names[p], "love")
		var leaver := p if state.rng.chance(0.5) else q
		state.person_homes[leaver] = -1 # finds a bed elsewhere next month


## Bitter rivals in the same tribe sometimes come to blows.
func _fights(state: WorldState) -> void:
	var keys: Array[String] = []
	for key: String in state.bonds:
		if int(state.bonds[key]) <= -70:
			keys.append(key)
	keys.sort()
	for key: String in keys:
		var parts := key.split("|")
		var a := state.index_of(parts[0].to_int())
		var b := state.index_of(parts[1].to_int())
		if a == -1 or b == -1 or state.person_tribes[a] != state.person_tribes[b]:
			continue
		if not People.is_adult(state, a) or not People.is_adult(state, b):
			continue
		if state.person_detained[a] > 0 or state.person_detained[b] > 0:
			continue
		var hot := People.has_trait(state, a, "fierce") or People.has_trait(state, b, "fierce")
		if not state.rng.chance((0.02 if hot else 0.005) * Society.effect(state, state.tribe_index(state.person_tribes[a]), "fights")):
			continue
		var strength_a := Genetics.express(state.person_genomes[a], "strength") + state.rng.randf() * 0.6
		var strength_b := Genetics.express(state.person_genomes[b], "strength") + state.rng.randf() * 0.6
		var loser := b if strength_a >= strength_b else a
		var winner := a if loser == b else b
		state.person_health[loser] = maxi(state.person_health[loser] - state.rng.randi_range(10, 30), 1)
		state.log_event("fight", {"tribe": state.person_tribes[a], "a": state.person_ids[winner], "a_name": state.person_names[winner], "b": state.person_ids[loser], "b_name": state.person_names[loser]})
		state.life(state.person_ids[winner], "Came to blows with %s, and won." % state.person_names[loser], "conflict")
		state.life(state.person_ids[loser], "Was beaten in a fight with %s." % state.person_names[winner], "conflict")
		state.meet(state.person_ids[a], state.person_ids[b], "fight")
		if state.rng.chance(0.03):
			state.kill_person(loser, "a fight", {"by": state.person_names[winner]})
