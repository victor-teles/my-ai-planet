class_name SocietySystem
extends SimSystem
## How each tribe's society lives and changes.
## Monthly: people earn by their work, and the ruler, the temple and the treasury take their cut;
## the treasury pays the guards and officials (and the ruler skims it); factories make their owners
## rich; savings are spent; everyone's loyalty follows how they are treated; and the tribe's
## legitimacy, unrest and fear, and the power of its five factions, move.
## Yearly: nobles and bonded are sorted out; the ruler puts forward the law that suits them best
## and may strike down one they dislike; the strongest other faction presses for its own law, and
## the ruler gives way or refuses; culture drifts; elections are held where there are votes;
## vassals pay tribute; and the year's society is written down for the history chart and the Oracle.
## Rulers want power: few give it away unless they are kind or wise, or are made to.

## What a month of work earns, in days of a laborer's keep, before skill. Guards and officials are
## paid from the treasury instead.
const INCOME := {
	"forager": 3.0, "hunter": 3.0, "fisher": 3.0, "farmer": 3.0, "woodcutter": 3.0, "quarrier": 3.0, "builder": 3.0,
	"toolmaker": 4.0, "healer": 5.0, "potter": 4.0, "weaver": 4.0, "shaman": 4.0,
	"miner": 4.0, "smith": 6.0, "scholar": 6.0, "merchant": 12.0, "factory_worker": 3.0,
}
const SALARY := {"guard": 7.0, "official": 9.0}
const FACTORY_PROFIT := 6.0 ## what each factory hand earns, per month, for the factory's owners
const SPEND := 0.04 ## share of savings spent each month
const LAW_MIN_POPULATION := 12 ## a handful of families lives by habit, not law
const PASS_AT := 3.5 ## how strongly a ruler must want a law to put it forward
## A law's power for the ruler, divided by this, is how much it draws them (the kind and wise less).
const POWER_APPEAL := 12.0
## Loyalty lost per point of freedom below 40.
const UNFREE_LOYALTY := 0.45
## Legitimacy lost for each dark law in force, whatever the culture: people know a cage.
const DARK_LAW_LEGITIMACY := 3.0
## Unrest held down per point of control.
const CONTROL_CALMS := 0.1
## Unrest added by the share of adults in custody: everybody knows someone who was taken.
const DETAINED_UNREST := 60.0
const REPEAL_AT := -1.0
const NOBLE_WEALTH := 3.0 ## times the median wealth that makes a family noble, where there are ranks
const ELECTION_YEARS := 8
const HISTORY_YEARS := 600


func get_id() -> String:
	return "society"


func get_interval() -> int:
	return WorldState.DAYS_PER_MONTH


func update(state: WorldState) -> void:
	for t: int in state.tribe_count():
		_reign(state, t)
		_earn(state, t)
		_loyalty(state, t)
		_legitimacy(state, t)
		_unrest(state, t)
		_fear(state, t)
		_power(state, t)
	if state.month() != 0:
		return
	for t: int in state.tribe_count():
		_classes(state, t)
		if state.tribe_population[t] >= LAW_MIN_POPULATION:
			var found := situation(state, t)
			_new_law(state, t, found)
			_old_law(state, t, found)
			_pressure(state, t, found)
		_drift(state, t)
		_election(state, t)
	_tribute(state)
	_write_history(state)


## Times the ruler's reign: a new face in the seat starts the clock again.
func _reign(state: WorldState, t: int) -> void:
	if state.tribe_ruler[t] != state.tribe_chiefs[t]:
		state.tribe_ruler[t] = state.tribe_chiefs[t]
		state.tribe_ruler_since[t] = state.tick


static func reign_years(state: WorldState, t: int) -> float:
	return (state.tick - state.tribe_ruler_since[t]) / float(WorldState.DAYS_PER_YEAR)


# --- Wealth -------------------------------------------------------------------------

func _earn(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var members := state.people_of(tribe)
	var tax := Society.effect(state, t, "tax")
	var tithe := Society.effect(state, t, "tithe")
	var share := Society.effect(state, t, "share")
	var corporate := Society.has_law(state, t, "corporate_charter")
	var credit := Society.flag(state, t, "social_credit")
	var taxed := 0.0
	var tithed := 0.0
	var pooled := 0.0
	var bonded_earnings := 0.0
	var shamans: Array[int] = []
	var adults: Array[int] = []
	var factory_hands := 0
	for p: int in members:
		if not People.is_adult(state, p):
			continue
		adults.append(p)
		var job := state.person_jobs[p]
		if job == "shaman":
			shamans.append(p)
		if job == "factory_worker":
			factory_hands += 1
		if not INCOME.has(job) or state.person_detained[p] > 0 or state.person_sick[p] > 0:
			continue
		var skill := state.person_skills[p][Jobs.skill_index(job)] / 100.0
		var earned := float(INCOME[job]) * (0.6 + 0.8 * skill)
		if credit and state.person_loyalty[p] < 35:
			earned *= 0.5 # a poor score closes doors
		var kept := earned * (1.0 - tax - tithe - share)
		taxed += earned * tax
		tithed += earned * tithe
		pooled += earned * share
		if state.person_status[p] == "bonded":
			bonded_earnings += kept
		else:
			state.person_wealth[p] += state.rng.round_stochastic(kept)
	# The bonded work for their creditors: the richest nobles, or the ruler.
	_pay_richest(state, adults, bonded_earnings, "noble", 3)
	# Factories make money for whoever owns them: the richest merchants, else the richest of all.
	if factory_hands > 0:
		var owners := "merchant" if _any_job(state, adults, "merchant") else ""
		_pay_richest(state, adults, factory_hands * FACTORY_PROFIT, owners, 3)
	# The temple's share feeds its shamans; the shared stores feed everyone alike.
	if not shamans.is_empty():
		for p: int in shamans:
			state.person_wealth[p] += state.rng.round_stochastic(tithed / shamans.size())
	else:
		taxed += tithed
	if not adults.is_empty():
		for p: int in adults:
			state.person_wealth[p] += state.rng.round_stochastic(pooled / adults.size())
	# Under a corporate charter, taxes go to the companies, not the state.
	if corporate:
		_pay_richest(state, adults, taxed, "merchant", 5)
	else:
		state.tribe_treasury[t] += taxed
	_pay_salaries(state, t, adults)
	for p: int in members:
		state.person_wealth[p] = clampi(state.person_wealth[p] - state.rng.round_stochastic(state.person_wealth[p] * SPEND), 0, 99999)


## The treasury pays its guards and officials, and the ruler takes what they think is theirs.
func _pay_salaries(state: WorldState, t: int, adults: Array[int]) -> void:
	for p: int in adults:
		var job := state.person_jobs[p]
		if not SALARY.has(job) or state.person_detained[p] > 0:
			continue
		var pay := float(SALARY[job])
		if state.tribe_treasury[t] >= pay:
			state.tribe_treasury[t] -= pay
			state.person_wealth[p] += roundi(pay)
		else:
			state.person_loyalty[p] = maxi(state.person_loyalty[p] - 2, 0) # unpaid guards grumble
	var ruler := state.chief_of(state.tribe_names[t])
	if ruler == -1 or state.tribe_treasury[t] <= 0.0:
		return
	var skim := 0.08 + 0.004 * maxf(float(state.tribe_culture[t].get("hierarchy", 0)), 0.0)
	if People.has_trait(state, ruler, "greedy"):
		skim += 0.25
	if People.has_trait(state, ruler, "proud"):
		skim += 0.08
	if People.has_trait(state, ruler, "kind"):
		skim *= 0.3
	if Society.top_faction(state, t) == "council":
		skim *= 0.4
	var taken := state.tribe_treasury[t] * minf(skim, 0.6)
	state.tribe_treasury[t] -= taken
	state.person_wealth[ruler] += roundi(taken)


## Splits an amount among the richest few adults of a class ("" for anyone, or a job id).
func _pay_richest(state: WorldState, adults: Array[int], amount: float, kind: String, count: int) -> void:
	if amount <= 0.0 or adults.is_empty():
		return
	var pool: Array[int] = []
	for p: int in adults:
		if state.person_detained[p] > 0 or state.person_status[p] == "bonded":
			continue
		if kind == "noble" and state.person_status[p] != "noble":
			continue
		if kind == "merchant" and state.person_jobs[p] != "merchant":
			continue
		pool.append(p)
	if pool.is_empty():
		if kind == "noble":
			pool.assign(adults.filter(func(p: int) -> bool: return state.person_status[p] != "bonded"))
		else:
			pool = adults.duplicate()
	pool.sort_custom(func(a: int, b: int) -> bool: return state.person_wealth[a] > state.person_wealth[b] or (state.person_wealth[a] == state.person_wealth[b] and a < b))
	var takers := pool.slice(0, mini(count, pool.size()))
	for p: int in takers:
		state.person_wealth[p] += state.rng.round_stochastic(amount / takers.size())


func _any_job(state: WorldState, people: Array[int], job: String) -> bool:
	for p: int in people:
		if state.person_jobs[p] == job:
			return true
	return false


# --- Loyalty, legitimacy, unrest, fear ----------------------------------------------

## Each adult's loyalty drifts toward what their life under these rulers earns: the rulers'
## legitimacy, their own mood, their class, the propaganda they hear, and their pride.
func _loyalty(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var propaganda := Society.effect(state, t, "propaganda")
	var credit := Society.flag(state, t, "social_credit")
	var top := Society.top_faction(state, t)
	var freedom := Society.freedom(state, t)
	var unequal := Society.inequality(state, t) >= 40
	var median := _median_wealth(state, t)
	var ruler := state.tribe_chiefs[t]
	for p: int in state.people_of(tribe):
		if not People.is_adult(state, p):
			continue
		if state.person_ids[p] == ruler:
			state.person_loyalty[p] = 100
			continue
		var target := 18.0 + 0.6 * state.tribe_legitimacy[t] + 0.4 * (state.person_mood[p] - 55) + propaganda
		if freedom < 40:
			target -= (40 - freedom) * UNFREE_LOYALTY
		match state.person_status[p]:
			"noble":
				target += 20.0
			"bonded":
				target -= 30.0
		if state.person_jobs[p] in ["guard", "official"]:
			target += 15.0
		if state.person_detained[p] > 0:
			target -= 30.0
		if unequal and state.person_wealth[p] * 3 < median:
			target -= 10.0
		if People.has_trait(state, p, "curious") and freedom < 40:
			target -= 10.0
		if People.has_trait(state, p, "proud") and state.person_status[p] != "noble" and Society.flag(state, t, "class_marriage"):
			target -= 8.0
		if People.has_trait(state, p, "devout") and top == "priests":
			target += 8.0
		if credit:
			target += 6.0 if state.person_loyalty[p] >= 60 else -6.0 # the score feeds itself
		var loyalty := state.person_loyalty[p]
		state.person_loyalty[p] = clampi(loyalty + state.rng.round_stochastic((target - loyalty) * 0.2), 0, 100)


func _median_wealth(state: WorldState, t: int) -> int:
	var wealth: Array[int] = []
	for p: int in Society.adults_of(state, t):
		wealth.append(state.person_wealth[p])
	if wealth.is_empty():
		return 0
	wealth.sort()
	return wealth[wealth.size() / 2]


## Do the people accept their rulers? Good times, faith, tradition and propaganda say yes;
## inequality beyond what their culture tolerates, laws they resent, hunger and fear say no.
func _legitimacy(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var culture: Dictionary = state.tribe_culture[t]
	var target := 50.0 + (Needs.mood(state, t) - 0.6) * 60.0
	if int(culture.get("piety", 0)) > 0:
		target += minf(float(state.tribe_work[t].get("shaman", 0.0)), 2.0) * 3.0
	target += minf(reign_years(state, t), 20.0) * 0.5
	target += Society.effect(state, t, "propaganda")
	var tolerance := 35.0 + 0.25 * float(culture.get("hierarchy", 0))
	target -= maxf(Society.inequality(state, t) - tolerance, 0.0) * 0.5
	for law: String in state.tribe_laws[t]:
		target -= maxf(-fit(state, t, law), 0.0) * 6.0
		if Laws.is_dystopian(law):
			target -= DARK_LAW_LEGITIMACY
	target -= state.tribe_fear[t] * 0.15
	if state.tribe_hungry_days[t] > 3:
		target -= 15.0
	if state.tribe_overlord[t]:
		target -= 8.0
	if state.ticks_since("war", tribe, 2 * WorldState.DAYS_PER_YEAR) < 2 * WorldState.DAYS_PER_YEAR:
		target -= 10.0 # the war was lost: data "tribe" is the loser
	var legitimacy := state.tribe_legitimacy[t]
	state.tribe_legitimacy[t] = clampi(legitimacy + state.rng.round_stochastic((target - legitimacy) * 0.1), 0, 100)


## Dissent, inequality, hunger and rulers nobody believes in stir the tribe; fear and watching
## keep it quiet, for a while.
func _unrest(state: WorldState, t: int) -> void:
	var adults := maxf(Society.adults_of(state, t).size(), 1.0)
	var target := 140.0 * Society.count_where(state, t, "dissident") / adults
	target += DETAINED_UNREST * Society.count_where(state, t, "detained") / adults
	target += maxf(Society.inequality(state, t) - 40.0, 0.0) * 0.4
	target += maxf(50.0 - state.tribe_legitimacy[t], 0.0) * 0.5
	if state.tribe_hungry_days[t] > 3:
		target += 20.0
	target -= state.tribe_fear[t] * 0.3 + Society.control(state, t) * CONTROL_CALMS
	var unrest := state.tribe_unrest[t]
	state.tribe_unrest[t] = clampi(unrest + state.rng.round_stochastic((maxf(target, 0.0) - unrest) * 0.15), 0, 100)


## Fear fades, but never below what the laws keep alive.
func _fear(state: WorldState, t: int) -> void:
	var floor_fear := roundi(float(state.law_sums(t)["fear"]))
	if state.kindness < 0:
		floor_fear += mini(-state.kindness * 3, 20) # a wrathful god is feared too
	state.tribe_fear[t] = clampi(maxi(state.tribe_fear[t] - 2, floor_fear), 0, 100)


## Who holds power: each faction's weight from the laws, the jobs people do, the buildings
## standing, who owns the wealth, and the tribe's culture. Power shifts slowly.
func _power(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var population := maxf(state.tribe_population[t], 1.0)
	var work: Dictionary = state.tribe_work[t]
	var culture: Dictionary = state.tribe_culture[t]
	var shares := _wealth_shares(state, t)
	var targets := {
		"ruler": 15.0 + minf(reign_years(state, t), 20.0) * 0.5 + 40.0 * float(shares["ruler"]),
		"council": 15.0 + (5.0 if state.knows(t, "writing") else 0.0) - Society.control(state, t) * 0.2,
		"priests": float(work.get("shaman", 0.0)) * 8.0 + 6.0 * state.count_buildings(tribe, "shrine") + 12.0 * state.count_buildings(tribe, "temple") + maxf(float(culture.get("piety", 0)), 0.0) * 0.25,
		"warriors": float(work.get("guard", 0.0)) * 150.0 / population + maxf(float(culture.get("martial", 0)), 0.0) * 0.25,
		"merchants": float(work.get("merchant", 0.0)) * 8.0 + 8.0 * state.count_buildings(tribe, "market") + 5.0 * state.count_buildings(tribe, "factory") + 40.0 * float(shares["merchants"]),
	}
	var ruler := state.chief_of(tribe)
	if ruler != -1:
		for trait_id: String in People.traits_of(state, ruler):
			targets["ruler"] = float(targets["ruler"]) + {"proud": 6.0, "fierce": 4.0, "greedy": 3.0}.get(trait_id, 0.0)
	if state.ticks_since("war", tribe, 5 * WorldState.DAYS_PER_YEAR) > 5 * WorldState.DAYS_PER_YEAR and war_lately(state, tribe, 5, true):
		targets["warriors"] = float(targets["warriors"]) + 8.0
	for law: String in state.tribe_laws[t]:
		var grants: Dictionary = Laws.LAWS[law]["power"]
		for faction: String in grants:
			targets[faction] = float(targets[faction]) + float(grants[faction])
	var powers: Dictionary = state.tribe_power[t]
	for faction: String in Society.FACTIONS:
		var now := int(powers.get(faction, 15))
		var target := clampf(float(targets[faction]), 0.0, 100.0)
		powers[faction] = clampi(now + state.rng.round_stochastic((target - now) * 0.1), 0, 100)


## The share of the tribe's wealth held by the ruler's family and by its merchants.
func _wealth_shares(state: WorldState, t: int) -> Dictionary:
	var tribe := state.tribe_names[t]
	var total := 0.0
	var ruler_family := 0.0
	var merchants := 0.0
	var ruler := state.chief_of(tribe)
	var house := state.person_families[ruler] if ruler != -1 else ""
	for p: int in state.people_of(tribe):
		var wealth := float(state.person_wealth[p])
		total += wealth
		if ruler != -1 and (p == ruler or (state.person_families[p] == house and state.person_status[p] == "noble")):
			ruler_family += wealth
		elif state.person_jobs[p] == "merchant":
			merchants += wealth
	if total <= 0.0:
		return {"ruler": 0.0, "merchants": 0.0}
	return {"ruler": ruler_family / total, "merchants": merchants / total}


## Whether the tribe fought a war in the last few years (only wars it won, if `won`).
static func war_lately(state: WorldState, tribe: String, years: int, won: bool = false) -> bool:
	for j: int in range(state.events.size() - 1, -1, -1):
		var event := state.events[j]
		if state.tick - int(event["tick"]) > years * WorldState.DAYS_PER_YEAR:
			return false
		if event["type"] != "war":
			continue
		var data: Dictionary = event["data"]
		if String(data.get("winner", "")) == tribe or (not won and String(data.get("loser", "")) == tribe):
			return true
	return false


# --- Classes ------------------------------------------------------------------------

## Where there are ranks, the ruling house and the richest families are noble, and nobility passes
## to children. Under bonded labor, adults with nothing fall into bondage, and their grown children
## with them. Without the law, the bonded go free; without ranks, nobility fades.
func _classes(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var hierarchy := int(state.tribe_culture[t].get("hierarchy", 0))
	var ranks := hierarchy >= 25 or (hierarchy >= 5 and (Society.flag(state, t, "hereditary") or Society.flag(state, t, "class_marriage") or Society.has_law(state, t, "chiefs_share")))
	var bondage := Society.flag(state, t, "bonded")
	var median := maxi(_median_wealth(state, t), 4)
	var raised: Array[String] = []
	var bound: Array[String] = []
	var freed := 0
	var ruler := state.chief_of(tribe)
	for p: int in state.people_of(tribe):
		var status := state.person_status[p]
		if status == "noble" and not ranks:
			state.person_status[p] = ""
			continue
		if status == "bonded" and not bondage:
			state.person_status[p] = ""
			state.life(state.person_ids[p], "Was freed from bondage.", "society")
			freed += 1
			continue
		if not People.is_adult(state, p) or status:
			continue
		if ranks and (p == ruler or (state.tribe_dynasty[t] and state.person_families[p] == state.tribe_dynasty[t]) or (state.person_wealth[p] >= median * NOBLE_WEALTH and state.person_wealth[p] >= 40)):
			state.person_status[p] = "noble"
			state.life(state.person_ids[p], "Was counted among the nobles of the %s." % tribe, "society")
			raised.append(state.person_names[p])
		elif bondage and (state.person_wealth[p] == 0 and state.rng.chance(0.35) or _parent_bonded(state, p)):
			state.person_status[p] = "bonded"
			state.life(state.person_ids[p], "Fell into debt bondage.", "society")
			bound.append(state.person_names[p])
	if raised.size() >= 2:
		state.log_event("nobles_raised", {"tribe": tribe, "count": raised.size(), "names": EconomySystem._names(raised)})
	if not bound.is_empty():
		state.log_event("bondage", {"tribe": tribe, "count": bound.size(), "names": EconomySystem._names(bound)})
	if freed >= 2:
		state.log_event("freed", {"tribe": tribe, "count": freed})


func _parent_bonded(state: WorldState, p: int) -> bool:
	for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
		var q := state.index_of(parent)
		if q != -1 and state.person_status[q] == "bonded":
			return true
	return false


# --- Laws ---------------------------------------------------------------------------

## What the times seem to call for in a tribe: situation -> true. Laws list the situations
## that make them seem needed ("when").
static func situation(state: WorldState, t: int) -> Dictionary:
	var tribe := state.tribe_names[t]
	var year := WorldState.DAYS_PER_YEAR
	var adults := Society.adults_of(state, t)
	var poor := 0
	for p: int in adults:
		if state.person_wealth[p] <= 3:
			poor += 1
	var fights := 0
	var raided := false
	for j: int in range(state.events.size() - 1, -1, -1):
		var event := state.events[j]
		if state.tick - int(event["tick"]) > 5 * year:
			break
		var data: Dictionary = event["data"]
		match String(event["type"]):
			"fight":
				if String(data.get("tribe", "")) == tribe and state.tick - int(event["tick"]) < 2 * year:
					fights += 1
			"raid":
				if String(data.get("victim", "")) == tribe and state.tick - int(event["tick"]) < 3 * year:
					raided = true
	var ruler := state.chief_of(tribe)
	var old_ruler := false
	if ruler != -1 and People.age(state, ruler) >= 50:
		for q: int in state.people_of(tribe):
			if (state.person_mothers[q] == state.tribe_chiefs[t] or state.person_fathers[q] == state.tribe_chiefs[t]) and People.is_adult(state, q):
				old_ruler = true
				break
	var frail := 0
	for p: int in state.people_of(tribe):
		if Genetics.frailty_copies(state.person_genomes[p]) > 0:
			frail += 1
	var dissent := Society.count_where(state, t, "dissident") / maxf(adults.size(), 1.0)
	return {
		"big": state.tribe_population[t] >= 40,
		"famine": state.ticks_since("famine", tribe, 2 * year) < 2 * year,
		"rich": Society.inequality(state, t) >= 45,
		"poor": poor >= adults.size() * 0.35 and adults.size() >= 6,
		"plague": state.ticks_since("epidemic", tribe, 3 * year) < 3 * year,
		"drought": state.drought_months_left > 0,
		"war": war_lately(state, tribe, 5),
		"raided": raided,
		"fights": fights >= 3,
		"dissent": dissent >= 0.12,
		"unrest": state.tribe_unrest[t] >= 45,
		"old_ruler": old_ruler,
		"frail": frail >= state.tribe_population[t] * 0.2,
		"smog": state.pollution >= 30.0,
	}


## How well a law suits a tribe's culture: positive if the people welcome it, negative if they resent it.
static func fit(state: WorldState, t: int, law: String) -> float:
	var total := 0.0
	var leanings: Dictionary = Laws.LAWS[law]["culture"]
	for axis: String in leanings:
		total += float(leanings[axis]) * float(state.tribe_culture[t].get(axis, 0)) / 40.0
	return total


## How much the ruler wants a law: their own nature, the times, the culture and the strongest faction.
static func appeal(state: WorldState, t: int, law: String, found: Dictionary) -> float:
	var info: Dictionary = Laws.LAWS[law]
	var score := fit(state, t, law)
	var ruler := state.chief_of(state.tribe_names[t])
	if ruler != -1:
		var traits: Dictionary = info["traits"]
		for trait_id: String in People.traits_of(state, ruler):
			score += float(traits.get(trait_id, 0.0))
	for need: String in info["when"]:
		if found.get(need, false):
			score += 1.5
	var faction := String(info["faction"])
	if faction == Society.top_faction(state, t):
		score += 1.5
	elif Society.power(state, t, faction) >= 40:
		score += 0.5
	# What it does for the ruler's own power. The kind and the wise care less.
	if ruler != -1:
		var selfish := 0.3 if People.has_trait(state, ruler, "kind") or People.has_trait(state, ruler, "wise") else 1.0
		score += float((info["power"] as Dictionary).get("ruler", 0)) / POWER_APPEAL * selfish
	return score


## How hard a faction presses for one of its laws: the times, the culture, and the power it brings them.
static func demand(state: WorldState, t: int, law: String, found: Dictionary, faction: String) -> float:
	var info: Dictionary = Laws.LAWS[law]
	var score := fit(state, t, law) + 1.0
	for need: String in info["when"]:
		if found.get(need, false):
			score += 1.5
	return score + float((info["power"] as Dictionary).get(faction, 0)) / 10.0


## Laws the tribe could take now: its age and knowledge allow them and nothing in force excludes them.
static func available(state: WorldState, t: int) -> Array[String]:
	var age := state.age_of(t)
	var open: Array[String] = []
	for law: String in Laws.ORDER:
		var info: Dictionary = Laws.LAWS[law]
		if Society.has_law(state, t, law) or int(info["age"]) > age:
			continue
		if String(info["tech"]) and not state.knows(t, String(info["tech"])):
			continue
		var blocked := false
		for other: String in state.tribe_laws[t]:
			var other_info: Dictionary = Laws.LAWS[other]
			if law in other_info["excludes"] or other in info["excludes"] or law in other_info.get("replaces", []):
				blocked = true
		if not blocked:
			open.append(law)
	return open


## Each year the ruler may put forward the law they want most. A strong free council blocks laws
## that take its freedoms, except in an emergency.
func _new_law(state: WorldState, t: int, found: Dictionary) -> void:
	var best := ""
	var best_score := PASS_AT
	for law: String in available(state, t):
		if law == "emergency_powers" and not (found["unrest"] or found["war"] or found["plague"]):
			continue
		var score := appeal(state, t, law, found) - 0.15 * state.tribe_laws[t].size()
		if score > best_score:
			best = law
			best_score = score
	if best.is_empty() or not state.rng.chance(0.5):
		return
	var info: Dictionary = Laws.LAWS[best]
	var emergency: bool = found["unrest"] or found["war"]
	if int(info["freedom"]) <= -8 and Society.power(state, t, "council") >= Society.power(state, t, "ruler") + 10 and not emergency:
		state.log_event("law_blocked", _law_data(state, t, best))
		state.tribe_legitimacy[t] = maxi(state.tribe_legitimacy[t] - 3, 0)
		return
	enact(state, t, best)


## Puts a law in force and lets everyone know. Laws the people resent cost the rulers legitimacy.
static func enact(state: WorldState, t: int, law: String, reason: String = "") -> void:
	if Society.has_law(state, t, law):
		return
	for old: String in Laws.LAWS[law].get("replaces", []):
		state.drop_law(t, old)
	state.pass_law(t, law)
	var data := _law_data(state, t, law)
	if reason:
		data["reason"] = reason
	state.log_event("law_passed", data)
	state.tribe_legitimacy[t] = clampi(state.tribe_legitimacy[t] - roundi(maxf(-fit(state, t, law), 0.0) * 5.0), 0, 100)
	state.tribe_fear[t] = maxi(state.tribe_fear[t], int(Laws.LAWS[law]["fear"]))
	var ruler := state.chief_of(state.tribe_names[t])
	if ruler != -1:
		state.life(state.person_ids[ruler], "Decreed %s." % Laws.name_of(law).to_lower(), "society")


static func repeal(state: WorldState, t: int, law: String, reason: String = "") -> void:
	if not Society.has_law(state, t, law):
		return
	state.drop_law(t, law)
	var data := _law_data(state, t, law)
	if reason:
		data["reason"] = reason
	state.log_event("law_repealed", data)
	if law == "hereditary_rule":
		state.tribe_dynasty[t] = ""


static func _law_data(state: WorldState, t: int, law: String) -> Dictionary:
	var data := {"tribe": state.tribe_names[t], "law": law}
	var ruler := state.chief_of(state.tribe_names[t])
	if ruler != -1:
		data["id"] = state.person_ids[ruler]
		data["name"] = state.person_names[ruler]
	return data


## The law the ruler likes least may be struck down, unless it keeps them in power. Emergency
## powers outlast their emergency unless a gentle ruler or a strong council gives them back.
func _old_law(state: WorldState, t: int, found: Dictionary) -> void:
	var worst := ""
	var worst_score := REPEAL_AT
	var ruler := state.chief_of(state.tribe_names[t])
	var gentle := ruler != -1 and (People.has_trait(state, ruler, "kind") or People.has_trait(state, ruler, "wise"))
	for law: String in Society.laws_of(state, t):
		if law == "emergency_powers":
			var calm: bool = not (found["unrest"] or found["war"] or found["plague"])
			if calm and (gentle or Society.top_faction(state, t) == "council") and state.rng.chance(0.4):
				repeal(state, t, law, "the emergency is over")
				return
			continue
		var score := appeal(state, t, law, found)
		var keeps_power := int((Laws.LAWS[law]["power"] as Dictionary).get("ruler", 0)) > 0
		if keeps_power and Society.power(state, t, "ruler") >= 55 and not gentle:
			continue # entrenched
		if score < worst_score:
			worst = law
			worst_score = score
	if worst and state.rng.chance(0.25):
		repeal(state, t, worst)


## The strongest faction other than the ruler presses for the law it wants most. A ruler who is
## weaker, gentle or no longer believed in gives way; otherwise they refuse, and the faction
## remembers it.
func _pressure(state: WorldState, t: int, found: Dictionary) -> void:
	var ruler_power := Society.power(state, t, "ruler")
	var faction := ""
	var faction_power := maxi(30, ruler_power - 5)
	for candidate: String in Society.FACTIONS:
		if candidate != "ruler" and Society.power(state, t, candidate) >= faction_power:
			faction = candidate
			faction_power = Society.power(state, t, candidate)
	if faction.is_empty():
		return
	var best := ""
	var best_score := 2.5
	for law: String in available(state, t):
		if String(Laws.LAWS[law]["faction"]) != faction or law == "emergency_powers":
			continue
		var score := demand(state, t, law, found, faction)
		if score > best_score:
			best = law
			best_score = score
	if best.is_empty() or not state.rng.chance(0.4):
		return
	var ruler := state.chief_of(state.tribe_names[t])
	var gentle := ruler != -1 and (People.has_trait(state, ruler, "kind") or People.has_trait(state, ruler, "wise"))
	var takes_power := int((Laws.LAWS[best]["power"] as Dictionary).get("ruler", 0)) < 0
	if faction_power >= ruler_power + 5 or (gentle and not takes_power) or state.tribe_legitimacy[t] < 35 or ruler == -1:
		enact(state, t, best, "pressed by %s" % Society.FACTION_NAMES[faction])
		return
	var data := _law_data(state, t, best)
	data["faction"] = faction
	state.log_event("law_refused", data)
	if faction == "council":
		state.tribe_unrest[t] = mini(state.tribe_unrest[t] + 8, 100)
		for p: int in Society.adults_of(state, t):
			if People.has_trait(state, p, "curious") or People.has_trait(state, p, "proud") or People.has_trait(state, p, "brave"):
				state.person_loyalty[p] = maxi(state.person_loyalty[p] - 8, 0)


# --- Culture ------------------------------------------------------------------------

## Culture drifts with the laws in force, the ruler's nature and what the tribe lived through.
func _drift(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var culture: Dictionary = state.tribe_culture[t]
	var push := {}
	for law: String in state.tribe_laws[t]:
		var pushes: Dictionary = Laws.LAWS[law]["push"]
		for axis: String in pushes:
			push[axis] = int(push.get(axis, 0)) + int(pushes[axis])
	var ruler := state.chief_of(tribe)
	if ruler != -1:
		for trait_id: String in People.traits_of(state, ruler):
			var lean: Dictionary = {
				"kind": {"hierarchy": -1}, "proud": {"hierarchy": 1}, "greedy": {"hierarchy": 1}, "devout": {"piety": 1},
				"curious": {"openness": 1}, "fierce": {"martial": 1}, "brave": {"martial": 1}, "wise": {"openness": 1},
			}.get(trait_id, {})
			for axis: String in lean:
				push[axis] = int(push.get(axis, 0)) + int(lean[axis])
	var year := WorldState.DAYS_PER_YEAR
	if war_lately(state, tribe, 1):
		push["martial"] = int(push.get("martial", 0)) + 2
	if state.ticks_since("famine", tribe, year) < year:
		push["piety"] = int(push.get("piety", 0)) + 1
		push["hierarchy"] = int(push.get("hierarchy", 0)) + 1
	if state.ticks_since("epidemic", tribe, year) < year:
		push["piety"] = int(push.get("piety", 0)) + 2
	if Needs.mood(state, t) >= 0.85:
		push["openness"] = int(push.get("openness", 0)) + 1
	# Machines and print loosen the hold of the old gods, unless the state holds it fast.
	if state.age_of(t) >= 3 and not Society.has_law(state, t, "state_religion"):
		push["piety"] = int(push.get("piety", 0)) - 1
	for axis: String in Society.CULTURE_AXES:
		var change := int(push.get(axis, 0)) + state.rng.randi_range(-1, 1)
		culture[axis] = clampi(int(culture.get(axis, 0)) + change, -100, 100)


# --- Elections ----------------------------------------------------------------------

## Where there are votes, every eight years the tribe chooses again. Where the radio and the score
## say who to love, the ruler always wins.
func _election(state: WorldState, t: int) -> void:
	if not Society.flag(state, t, "elections") or state.tribe_population[t] < LAW_MIN_POPULATION:
		return
	var tribe := state.tribe_names[t]
	if (state.year() - WorldState.year_of(state.tribe_founded[t])) % ELECTION_YEARS != 0:
		return
	var incumbent := state.chief_of(tribe)
	if incumbent == -1:
		return
	if Society.effect(state, t, "propaganda") >= 10.0 or Society.control(state, t) >= 70:
		state.log_event("election", {"tribe": tribe, "id": state.person_ids[incumbent], "name": state.person_names[incumbent], "rigged": 1})
		return
	var members := state.people_of(tribe)
	var top := Society.top_faction(state, t)
	var best := incumbent
	var best_score := People.claim(state, incumbent, members, top) + 8.0 # the known face
	for p: int in members:
		if p == incumbent or not People.is_adult(state, p) or People.age(state, p) < 25 or state.person_detained[p] > 0:
			continue
		var score := People.claim(state, p, members, top) + state.rng.randf() * 10.0
		if score > best_score:
			best = p
			best_score = score
	if best == incumbent:
		state.log_event("election", {"tribe": tribe, "id": state.person_ids[incumbent], "name": state.person_names[incumbent], "kept": 1})
		return
	state.tribe_chiefs[t] = state.person_ids[best]
	state.log_event("election", {"tribe": tribe, "id": state.person_ids[best], "name": state.person_names[best], "loser": state.person_names[incumbent]})
	state.life(state.person_ids[best], "Was elected to lead the %s." % tribe, "chief")
	state.life(state.person_ids[incumbent], "Lost the election to %s." % state.person_names[best], "chief")


# --- Vassals ------------------------------------------------------------------------

## Vassals send food and coin to their overlord every year, and resent it.
func _tribute(state: WorldState) -> void:
	for t: int in state.tribe_count():
		var lord := state.tribe_index(state.tribe_overlord[t])
		if lord == -1:
			continue
		var food := state.tribe_food[t] * 0.1
		var coin := state.tribe_treasury[t] * 0.25
		state.tribe_food[t] -= food
		state.tribe_food[lord] += food
		state.tribe_treasury[t] -= coin
		state.tribe_treasury[lord] += coin
		state.change_relation(state.tribe_names[t], state.tribe_names[lord], -2)


# --- History ------------------------------------------------------------------------

func _write_history(state: WorldState) -> void:
	var tribes := {}
	for t: int in state.tribe_count():
		var m := Society.metrics(state, t)
		tribes[state.tribe_names[t]] = {
			"freedom": m["freedom"], "control": m["control"], "inequality": m["inequality"], "fear": m["fear"],
			"dystopia": m["dystopia"], "government": m["government"], "age": m["age"], "population": state.tribe_population[t],
		}
	state.society_history.append({"year": state.year(), "pollution": roundi(state.pollution), "tribes": tribes})
	if state.society_history.size() > HISTORY_YEARS:
		state.society_history.remove_at(0)
