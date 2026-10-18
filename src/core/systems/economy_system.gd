class_name EconomySystem
extends SimSystem
## Every day: the workers bring in food, wood and stone, the crafts keep up the tribe's tools,
## clothes and jars, everyone eats, stores spoil, and builders put a day into the current project.
## How much each job gets done is worked out monthly by the work system (state.tribe_work).
## The island's biome scales what the land gives; known techs, the laws and the age's better tools
## scale what people get out of it. Miners dig ore for the smiths, and factories turn out tools,
## cloth and jars by the cartload, and smoke for everyone.

const EATS := {"infant": 0.35, "child": 0.65, "youth": 0.9, "adult": 1.0, "elder": 0.85}
## Per month of the year (0 is deep winter).
const FORAGE_SEASON: Array[float] = [0.35, 0.45, 0.8, 1.05, 1.2, 1.3, 1.35, 1.35, 1.3, 1.1, 0.8, 0.5]
const HUNT_SEASON: Array[float] = [0.7, 0.7, 0.85, 0.95, 1.0, 1.05, 1.1, 1.1, 1.2, 1.2, 1.1, 0.85]
const FISH_SEASON: Array[float] = [0.5, 0.6, 0.9, 1.1, 1.2, 1.25, 1.25, 1.2, 1.1, 1.0, 0.8, 0.6]
const FARM_SEASON: Array[float] = [0.0, 0.0, 0.15, 0.3, 0.45, 0.6, 0.9, 1.5, 2.4, 1.7, 0.4, 0.05]
## Food (or wood, stone) per unit of work per day, before seasons, tools and crowding.
const RATES := {"forager": 2.3, "hunter": 2.9, "fisher": 2.6, "farmer": 4.4, "woodcutter": 1.6, "quarrier": 1.0, "miner": 0.6}
const WILD_WORKERS := 110.0 ## valley-wide foragers at which wild food halves
const FARMERS_PER_FIELD := 3.0
const SPOIL_PER_DAY := 0.0035
const STORE_DAYS := 100.0 ## food a tribe can keep, per person
const STOREHOUSE_DAYS := 70.0 ## more room per storehouse
const GOODS_WEAR := 0.004 ## tools, clothes and jars wear out this share a day
const GOODS_MADE := 0.1 ## per unit of craft work, divided by the tribe's size
const FAMINE_QUIET_DAYS := 180
## How a day's shortfall becomes hunger: the share of the day's food missing, times this, is the
## chance it counts as a hungry day. Each hungry day costs everyone health at month's end.
const HUNGER_SHORTFALL := 1.0
const TOOL_POWER: Array[float] = [0.35, 0.5, 0.65, 0.85, 1.0] ## by age: what good tools add to work
const METAL_PER_SMITH := 0.06 ## metal a smith works through each day
const FACTORY_GOODS := 0.35 ## goods per unit of factory work, against GOODS_MADE for a craftsman
const SMOKE := 0.004 ## pollution per unit of factory work per day


func get_id() -> String:
	return "economy"


func update(state: WorldState) -> void:
	var eaters := _eaters(state)
	var wild := 0.0
	for t: int in state.tribe_count():
		wild += float(state.tribe_work[t].get("forager", 0.0))
	var wild_yield := 1.0 / (1.0 + wild / WILD_WORKERS)
	for t: int in state.tribe_count():
		_produce(state, t, wild_yield)
		_eat(state, t, float(eaters.get(state.tribe_names[t], 0.0)))
		_build(state, t)


## Food eaten per day in each tribe: children and elders eat less.
func _eaters(state: WorldState) -> Dictionary:
	var eaters := {}
	for p: int in state.person_ids.size():
		var tribe := state.person_tribes[p]
		eaters[tribe] = float(eaters.get(tribe, 0.0)) + float(EATS[People.stage(state, p)])
	return eaters


func _produce(state: WorldState, t: int, wild_yield: float) -> void:
	var work: Dictionary = state.tribe_work[t]
	var world := state.world
	var known := state.tribe_knowledge[t]
	var m := state.month()
	var tools := 1.0 + TOOL_POWER[state.age_of(t)] * state.tribe_tools[t]
	var rain := clampf(state.rainfall, 0.45, 1.3)
	var thirst := lerpf(0.5, 1.0, Needs.water(state, t))
	var gather := People.chief_effect(state, state.tribe_names[t], "gather") * Society.effect(state, t, "work")
	var water_fish := clampf(state.water_level[state.tribe_water[t]] * 1.6, 0.2, 1.0)
	var food := 0.0
	food += float(work.get("forager", 0.0)) * RATES["forager"] * FORAGE_SEASON[m] * rain * wild_yield * WorldGen.rate(world, "forage")
	var hunter_work := float(work.get("hunter", 0.0))
	# Already added to the stores. A second add would pay for the same kill twice.
	AnimalSystem.meat_from_hunt(state, t, hunter_work)
	food += float(work.get("fisher", 0.0)) * RATES["fisher"] * FISH_SEASON[m] * water_fish * WorldGen.rate(world, "fish")
	var field_room := state.count_buildings(state.tribe_names[t], "field") * FARMERS_PER_FIELD
	# Watered fields care less about the rain.
	var dry := 0.75 if "irrigation" in known else 0.5
	var farm := RATES["farmer"] * WorldGen.rate(world, "farm") * state.tech_bonus(t, "farm") * (1.0 - state.pollution / 250.0)
	food += minf(float(work.get("farmer", 0.0)), field_room) * farm * FARM_SEASON[m] * lerpf(dry, 1.0, minf(rain, 1.0))
	state.tribe_food[t] += food * tools * gather * thirst
	var haul := tools * state.tech_bonus(t, "haul") * Society.effect(state, t, "work")
	state.tribe_wood[t] += float(work.get("woodcutter", 0.0)) * RATES["woodcutter"] * haul * WorldGen.rate(world, "wood")
	state.tribe_stone[t] += float(work.get("quarrier", 0.0)) * RATES["quarrier"] * haul * WorldGen.rate(world, "stone")
	# Miners dig the ore of the age (copper, then iron); there's little where the island has none.
	var ore := WorldGen.ore(world, "iron" if "iron_working" in known else "copper")
	state.tribe_metal[t] += float(work.get("miner", 0.0)) * RATES["miner"] * haul * maxf(ore, 0.15)
	var size := maxf(state.tribe_population[t], 8.0)
	var workshop := 1.5 if state.count_buildings(state.tribe_names[t], "workshop") > 0 else 1.0
	var made_tools := float(work.get("toolmaker", 0.0)) * GOODS_MADE * workshop
	var smithing := minf(float(work.get("smith", 0.0)) * METAL_PER_SMITH, state.tribe_metal[t])
	state.tribe_metal[t] -= smithing
	made_tools += smithing / METAL_PER_SMITH * GOODS_MADE * 2.0
	var factory := float(work.get("factory_worker", 0.0))
	var goods := factory * FACTORY_GOODS * GOODS_MADE
	state.tribe_tools[t] = clampf(state.tribe_tools[t] * (1.0 - GOODS_WEAR) + (made_tools + goods) / size, 0.0, 1.0)
	state.tribe_cloth[t] = clampf(state.tribe_cloth[t] * (1.0 - GOODS_WEAR) + (float(work.get("weaver", 0.0)) * GOODS_MADE + goods) / size, 0.0, 1.0)
	state.tribe_pots[t] = clampf(state.tribe_pots[t] * (1.0 - GOODS_WEAR) + (float(work.get("potter", 0.0)) * GOODS_MADE + goods) / size, 0.0, 1.0)
	state.pollution = minf(state.pollution + factory * SMOKE * Society.effect(state, t, "pollution"), 100.0)


func _eat(state: WorldState, t: int, eaten: float) -> void:
	var population := state.tribe_population[t]
	var food := state.tribe_food[t] - eaten
	if food < 0.0:
		# Going a quarter short is half a hungry day, half short or worse a whole one: what was
		# gathered still feeds some.
		var short := minf(HUNGER_SHORTFALL * -food / maxf(eaten, 0.01), 1.0)
		food = 0.0
		if state.rng.chance(short):
			state.tribe_hungry_days[t] += 1
		var tribe := state.tribe_names[t]
		if state.tribe_hungry_days[t] == 3 and state.ticks_since("famine", tribe, FAMINE_QUIET_DAYS) > FAMINE_QUIET_DAYS:
			state.log_event("famine", {"tribe": tribe})
	var stores := 1 + state.count_buildings(state.tribe_names[t], "storehouse")
	var spoil := SPOIL_PER_DAY * (1.0 - 0.55 * state.tribe_pots[t]) / (1.0 + 0.6 * (stores - 1))
	food -= food * spoil
	var room := population * (STORE_DAYS + STOREHOUSE_DAYS * (stores - 1)) * (1.0 + 0.4 * state.tribe_pots[t])
	state.tribe_food[t] = minf(food, room)


## The builders put in their day. A finished building may give a family a home.
func _build(state: WorldState, t: int) -> void:
	var project := state.tribe_project[t]
	if project == -1:
		return
	var b := state.building_index(project)
	if b == -1:
		state.tribe_project[t] = -1
		return
	var work := float(state.tribe_work[t].get("builder", 0.0))
	state.building_progress[b] += state.rng.round_stochastic(work)
	var needed := int(Buildings.TYPES[state.building_types[b]]["work"])
	if state.building_progress[b] < needed:
		return
	state.building_progress[b] = needed
	state.building_done[b] = state.tick
	state.tribe_project[t] = -1
	var tribe := state.tribe_names[t]
	var builders: Array[String] = []
	for p: int in state.people_of(tribe):
		if state.person_jobs[p] == "builder":
			builders.append(state.person_names[p])
			state.life(state.person_ids[p], "Helped build the %s's %s." % [tribe, Buildings.name_of(state.building_types[b])], "work")
	state.log_event("building_done", {
		"tribe": tribe, "building": state.building_types[b], "building_id": project,
		"builders": _names(builders),
	})
	if Buildings.is_home(state.building_types[b]):
		WorkSystem.settle_homes(state, t)


static func _names(names: Array[String]) -> String:
	if names.size() <= 1:
		return "".join(names)
	if names.size() > 4:
		return "%s and %d others" % [", ".join(names.slice(0, 3)), names.size() - 3]
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[-1]]
