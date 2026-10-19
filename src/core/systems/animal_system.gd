class_name AnimalSystem
extends SimSystem
## Once a month the wild animals lose condition, die, breed and are hunted by wolves and big cats.
## Every day, hunters are paid by how much of each seeded herd is still alive. The system keeps no state of its own.

const CAP := 240 ## births stop here; hunting and predators can go below it
## The valley holds this many herds of each wild species. One herd of eight deer could not
## outbreed a camp's few kills a year plus old age, and the taiga starved when it was gone.
const HERDS := 3
## Never fewer than this of a species: three bears were one or two mothers, and died out by bad luck.
const FEWEST := 6
## A species stops breeding at this many times its seeded count: room for the herd to grow
## past the hunt, without one fast breeder filling the island's cap and stopping every other birth.
const ROOM := 2
## Kept per species in WorldState.animal_tally, in this order. Meat is food; the rest are heads.
const TALLY: Array[String] = ["born", "aged", "starved", "preyed", "hunted", "meat"]
const ADULT_YEARS := 1
const REST_AT := 80
const REST_STEP := 5
const DROUGHT_LOSS := 4
const THIN_COAT := 0.40 ## grazers and browsers this thin suffer in the two deep-winter months
const COAT_LOSS := 18.0
## Longevity 0 lives this share of the written lifespan, longevity 1 the high share. 0.5 is exact.
const LIFE_LOW := 0.55
const LIFE_HIGH := 1.45
const FERTILITY_BASE := 0.2
const FERTILITY_SPAN := 0.75
## A still, bold animal is an easy shot. A fast wary one is harder. Division, not pow:
## the chance has to be the same on every platform.
## Census of seed 42: winter forage cannot replace the 2.9 rate, and a carcass of a few dozen meals cannot either.
const HUNT_EASY := 0.9
const HUNT_DIV := 899.0
const HUNT_FLOOR := 0.0005
## A prey this fast, or faster, gets away. Wolves clear the slow, not the whole herd.
const SLOW_PREY := 0.22
const HUNTERS: Array[String] = ["wolf", "cat"]


func get_id() -> String:
	return "animals"


func get_interval() -> int:
	return WorldState.DAYS_PER_MONTH


func update(state: WorldState) -> void:
	_condition(state)
	_deaths(state)
	_breed(state)
	predate(state)
	_note_wipes(state)


## Wild herds for this biome. Half the animals are female, alternating after one coin flip.
static func seed(state: WorldState) -> void:
	var table := Species.animal_table()
	for species_id: String in Species.wild_in(String(state.world.get("biome", ""))):
		var info := Species.get_species(species_id)
		state.animal_seeded.append(species_id)
		var herd := maxi(int(info["herd"]) * HERDS, FEWEST)
		state.animal_seeded_counts.append(herd)
		var female := state.rng.chance(0.5)
		var span := int(info["lifespan"]) * WorldState.DAYS_PER_YEAR
		for _n: int in herd:
			var sex := "f" if female else "m"
			female = not female
			var age := state.rng.randi_range(0, span)
			var condition := state.rng.randi_range(70, 100)
			var genome := Genetics.founder(state.rng, 0, table)
			state.add_animal(species_id, sex, state.tick - age, genome, condition)


## Food for this tribe today, paid once from the herds that were alive before any kill in this call.
## Scale is what the camp brings to every food job (crowding, tools, the chief, water); 1 in tests.
## An empty valley pays nothing and keeps no credit. The death is not a second pile of meat.
static func meat_from_hunt(state: WorldState, tribe_index: int, hunter_work: float, scale: float = 1.0) -> float:
	var prey := _hunt_target(state)
	if prey == -1:
		state.tribe_hunt_credit[tribe_index] = 0.0
		_note_wipes(state)
		return 0.0
	var gained := 0.0
	if hunter_work > 0.0:
		var season := EconomySystem.HUNT_SEASON[state.month()]
		var hunt_rate := WorldGen.rate(state.world, "hunt")
		var shares := _hunt_shares(state)
		var full := 0.0
		for species_id: String in shares:
			full += float(shares[species_id])
		gained = hunter_work * EconomySystem.RATES["hunter"] * season * hunt_rate * scale * full
		# Each herd's meat is its share of the day: a species that is gone feeds nobody.
		for species_id: String in shares:
			if float(shares[species_id]) > 0.0:
				tally(state, species_id, "meat", gained * float(shares[species_id]) / full)
		var table := Species.animal_table()
		prey = _hunt_target(state, true)
		var genome := state.animal_genomes[prey]
		var evade := Genetics.express(genome, "speed", table) + Genetics.express(genome, "wariness", table)
		# A dangerous animal (a bear, a boar) is stalked warily and often let go.
		var risk := float(Species.get_species(state.animal_species[prey]).get("danger", 0.0))
		var credit := state.tribe_hunt_credit[tribe_index] + hunter_work * _hunt_chance(evade) * (1.0 - risk)
		var tribe := state.tribe_names[tribe_index]
		while credit >= 1.0 and prey != -1:
			credit -= 1.0
			var species_id := state.animal_species[prey]
			var injured := false
			var danger := float(Species.get_species(species_id).get("danger", 0.0))
			if danger >= 0.4:
				injured = state.rng.chance(danger * 0.15)
			state.remove_animal(prey)
			tally(state, species_id, "hunted", 1)
			var data := {"species": species_id, "tribe": tribe}
			if injured:
				data["injured"] = true
			state.log_event("hunt", data)
			prey = _hunt_target(state, true)
		# An empty valley does not store the next kill.
		state.tribe_hunt_credit[tribe_index] = snappedf(credit, WorldState.FLOAT_STEP) if prey != -1 else 0.0
	state.tribe_food[tribe_index] += gained
	_note_wipes(state)
	return gained


## Wolves and big cats take the slowest prey, then the weakest, when that animal is slow
## enough to catch. One kill a month between them; a pack that each ate every month would
## empty a seeded herd before it could breed.
static func predate(state: WorldState) -> void:
	if not _any_hunter(state):
		return
	var victim := _slowest_prey(state)
	if victim == -1:
		return
	var speed := Genetics.express(state.animal_genomes[victim], "speed", Species.animal_table())
	if speed > SLOW_PREY:
		return
	tally(state, state.animal_species[victim], "preyed", 1)
	state.remove_animal(victim)


static func prey_count(state: WorldState) -> int:
	var count := 0
	for i: int in state.animal_ids.size():
		if _is_prey(state, i):
			count += 1
	return count


## Each prey species' living count over its seeded count, capped at full, weighted by its share
## of the seeded prey. A herd that grew past its seeding cannot stand in for one that is gone.
## No prey is empty. A hand-built herd with no seeded count is full.
static func hunt_fullness(state: WorldState) -> float:
	var full := 0.0
	var shares := _hunt_shares(state)
	for species_id: String in shares:
		full += float(shares[species_id])
	return full


## All the food hunters have brought in, over every species.
static func hunter_meat(state: WorldState) -> float:
	var meat := 0.0
	for species_id: String in state.animal_tally:
		meat += float(state.animal_tally[species_id]["meat"])
	return meat


## Prey alive at seeding, summed over the seeded prey species.
static func prey_seeded(state: WorldState) -> int:
	var total := 0
	for s: int in state.animal_seeded.size():
		if is_prey_species(state.animal_seeded[s]):
			total += state.animal_seeded_counts[s]
	return total


## species -> its part of the day's fullness. Seeded prey species only, in seeding order;
## a hand-built world with nothing seeded counts every living prey species as one full herd.
static func _hunt_shares(state: WorldState) -> Dictionary:
	var alive := {}
	for i: int in state.animal_ids.size():
		if _is_prey(state, i):
			alive[state.animal_species[i]] = int(alive.get(state.animal_species[i], 0)) + 1
	var shares := {}
	var seeded := prey_seeded(state)
	if seeded <= 0:
		for species_id: String in alive:
			shares[species_id] = 1.0 / float(alive.size())
		return shares
	for s: int in state.animal_seeded.size():
		var species_id := state.animal_seeded[s]
		if is_prey_species(species_id):
			shares[species_id] = float(mini(int(alive.get(species_id, 0)), state.animal_seeded_counts[s])) / float(seeded)
	return shares


## Add to a species' running tally (see TALLY). A species gets its row the first time it is counted.
static func tally(state: WorldState, species_id: String, key: String, amount: float) -> void:
	if not state.animal_tally.has(species_id):
		var fresh := {}
		for field: String in TALLY:
			fresh[field] = 0.0 if field == "meat" else 0
		state.animal_tally[species_id] = fresh
	var row: Dictionary = state.animal_tally[species_id]
	if key == "meat":
		row[key] = snappedf(float(row[key]) + amount, WorldState.FLOAT_STEP)
	else:
		row[key] = int(row[key]) + int(amount)


static func _predator_count(state: WorldState) -> int:
	var count := 0
	for species_id: String in state.animal_species:
		if species_id in HUNTERS:
			count += 1
	return count


static func _hunt_chance(evade: float) -> float:
	return clampf(HUNT_EASY / (1.0 + HUNT_DIV * evade), HUNT_FLOOR, HUNT_EASY)


static func _condition(state: WorldState) -> void:
	var table := Species.animal_table()
	var winter := state.month() == 0 or state.month() == 1
	for i: int in state.animal_ids.size():
		var diet := String(Species.get_species(state.animal_species[i]).get("diet", ""))
		if diet != "grazer" and diet != "browser":
			continue
		var loss := 0
		if state.drought_months_left > 0:
			loss += DROUGHT_LOSS
		if winter:
			var coat := Genetics.express(state.animal_genomes[i], "coat", table)
			if coat < THIN_COAT:
				loss += roundi((THIN_COAT - coat) * COAT_LOSS)
		var condition := state.animal_condition[i]
		if loss > 0:
			state.animal_condition[i] = maxi(condition - loss, 0)
		elif condition < REST_AT:
			state.animal_condition[i] = mini(condition + REST_STEP, REST_AT)


static func _deaths(state: WorldState) -> void:
	var table := Species.animal_table()
	for i: int in range(state.animal_ids.size() - 1, -1, -1):
		var info := Species.get_species(state.animal_species[i])
		var longevity := Genetics.express(state.animal_genomes[i], "longevity", table)
		var limit := float(info["lifespan"]) * lerpf(LIFE_LOW, LIFE_HIGH, longevity) * float(WorldState.DAYS_PER_YEAR)
		var aged := float(state.tick - state.animal_born[i]) > limit
		if state.animal_condition[i] <= 0 or aged:
			tally(state, state.animal_species[i], "starved" if state.animal_condition[i] <= 0 else "aged", 1)
			state.remove_animal(i)


static func _breed(state: WorldState) -> void:
	if state.animal_ids.size() >= CAP:
		return
	var table := Species.animal_table()
	var month := state.month()
	var females: Array[int] = []
	for i: int in state.animal_ids.size():
		if state.animal_sex[i] != "f" or not _adult(state, i):
			continue
		if int(Species.get_species(state.animal_species[i]).get("breed_month", -1)) != month:
			continue
		females.append(i)
	for mother: int in females:
		if state.animal_ids.size() >= CAP:
			return
		var species_id := state.animal_species[mother]
		# Wolf numbers follow the prey. A pack larger than the herd does not whelp, or it fills the cap and the prey never breed again.
		if species_id in HUNTERS and prey_count(state) <= _predator_count(state):
			continue
		if living(state, species_id) >= _room(state, species_id):
			continue
		var sire := _sire(state, species_id)
		if sire == -1:
			continue
		var fertility := Genetics.express(state.animal_genomes[mother], "fertility", table)
		if not state.rng.chance(clampf(FERTILITY_BASE + FERTILITY_SPAN * fertility, 0.0, 0.95)):
			continue
		var litter := int(Species.get_species(species_id)["litter"])
		for _young: int in litter:
			if state.animal_ids.size() >= CAP:
				return
			var heredity: Dictionary = Genetics.inherit(state.rng, state.animal_genomes[mother], state.animal_genomes[sire], table)
			var sex := "f" if state.rng.chance(0.5) else "m"
			state.add_animal(species_id, sex, state.tick, heredity["genome"], 60)
			tally(state, species_id, "born", 1)


## How many of a species the valley feeds: ROOM times its seeding, or the whole cap when it was never seeded.
static func _room(state: WorldState, species_id: String) -> int:
	var s := state.animal_seeded.find(species_id)
	if s == -1:
		return CAP
	return state.animal_seeded_counts[s] * ROOM


## How many of a species are alive.
static func living(state: WorldState, species_id: String) -> int:
	var total := 0
	for other: String in state.animal_species:
		if other == species_id:
			total += 1
	return total


static func _sire(state: WorldState, species_id: String) -> int:
	var table := Species.animal_table()
	var best := -1
	var best_score := -1.0
	for i: int in state.animal_ids.size():
		if state.animal_species[i] != species_id or state.animal_sex[i] != "m" or not _adult(state, i):
			continue
		var genome := state.animal_genomes[i]
		var score := Genetics.express(genome, "size", table) + Genetics.express(genome, "horns", table)
		if best == -1 or score > best_score:
			best = i
			best_score = score
	return best


static func _adult(state: WorldState, index: int) -> bool:
	return state.tick - state.animal_born[index] >= ADULT_YEARS * WorldState.DAYS_PER_YEAR


static func _any_hunter(state: WorldState) -> bool:
	for i: int in state.animal_species.size():
		if state.animal_species[i] in HUNTERS:
			return true
	return false


## Lowest speed, then lowest condition, then the earliest index.
static func _slowest_prey(state: WorldState) -> int:
	var table := Species.animal_table()
	var best := -1
	var best_speed := 0.0
	var best_condition := 0
	for i: int in state.animal_ids.size():
		if not _is_prey(state, i):
			continue
		var speed := Genetics.express(state.animal_genomes[i], "speed", table)
		var condition := state.animal_condition[i]
		if best == -1 or speed < best_speed or (speed == best_speed and condition < best_condition):
			best = i
			best_speed = speed
			best_condition = condition
	return best


## Hunters chase the easiest animal: lowest speed plus wariness, then lowest condition.
## Tracking, they come on one living prey animal drawn at random, so a common species is met
## more often than a rare one, and chase the easiest of that kind. Without tracking, any species.
static func _hunt_target(state: WorldState, track: bool = false) -> int:
	var table := Species.animal_table()
	var kind := ""
	if track:
		var prey: Array[int] = []
		for i: int in state.animal_ids.size():
			if _is_prey(state, i):
				prey.append(i)
		if prey.is_empty():
			return -1
		kind = state.animal_species[prey[state.rng.pick_index(prey.size())]]
	var best := -1
	var best_evade := 0.0
	var best_condition := 0
	for i: int in state.animal_ids.size():
		if not _is_prey(state, i) or (kind != "" and state.animal_species[i] != kind):
			continue
		var genome := state.animal_genomes[i]
		var evade := Genetics.express(genome, "speed", table) + Genetics.express(genome, "wariness", table)
		var condition := state.animal_condition[i]
		if best == -1 or evade < best_evade or (evade == best_evade and condition < best_condition):
			best = i
			best_evade = evade
			best_condition = condition
	return best


static func _is_prey(state: WorldState, index: int) -> bool:
	return is_prey_species(state.animal_species[index])


static func is_prey_species(species_id: String) -> bool:
	var info := Species.get_species(species_id)
	if String(info.get("diet", "")) == "predator":
		return false
	return "meat" in info.get("gives", [])


static func _note_wipes(state: WorldState) -> void:
	for species_id: String in state.animal_seeded:
		if state.animal_wiped.has(species_id):
			continue
		if living(state, species_id) == 0:
			state.animal_wiped.append(species_id)
			state.log_event("hunt", {"species": species_id, "wiped": true})
