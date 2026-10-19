class_name Diorama
extends Node3D
## The world as a floating-island diorama. Reads the simulation each frame and keeps the
## view in step with it; never writes to the simulation. Each tribe is a Settlement; the
## island's trees, rocks, bushes and shores are WorkSites the villagers walk out to. The world
## recipe shapes the island and its biome (BiomeLook); the Atmosphere darkens with its society.

const SKY_SHADER := preload("res://art/shaders/sky_dusk.gdshader")
const WATER_SHADER := preload("res://art/shaders/water.gdshader")
const CLOUD_SEA_COUNT := 46
const POPUP_SECONDS := 3.2
## Bursts of small events merge into one pop-up; past this rate small ones are dropped (EventPacer).
const MAX_POPUPS_PER_SECOND := 2.5
const MAX_POPUP_BURST := 4.0
## Events that get a floating pop-up, and the words on it.
const POPUP_TYPES: Array[String] = [
	"birth", "death", "marriage", "discovery", "building_done", "new_chief", "tribe_split", "tribes_merged",
	"war", "famine", "epidemic", "drought_started", "drought_ended", "miracle", "tribe_extinct", "newcomers", "job",
	"proposal_refused", "adoption", "tech_spread", "gifts",
	"new_age", "destiny", "revolution", "coup", "capture", "uprising_crushed", "protests", "new_dynasty", "vassal", "disaster",
]

var shape: IslandShape
var sites: WorkSites
var camera_rig := CameraRig.new()
var atmosphere: Atmosphere
var herds := Herds.new() ## the animals

var _camps: Dictionary = {} ## tribe name -> Settlement
var _next_slot := 0
var _last_event_id := -1
var _last_meeting_id := -1
var _dryness := 0.0
var _snow := 0.0
var _snow_depth := 0.0 ## how white this island's deepest winter gets (BiomeLook.snow)
var _look: Dictionary = {}
var _water_material := ShaderMaterial.new()
var _clouds := Node3D.new()
var _sun := DirectionalLight3D.new()
var _rain := CPUParticles3D.new()
var _selected := ""
var _focused_person := -1
var _focus_label := ""
var _popup_frame := -1 ## the frame the last pop-up appeared in
var _popups_this_frame: Dictionary = {} ## where -> how many pop-ups started there this frame
var _popups := EventPacer.new(MAX_POPUPS_PER_SECOND, MAX_POPUP_BURST)
var _last_seen: Dictionary = {} ## person id -> [tribe, world position], to walk movers to their new home
var _pond: MeshInstance3D
var _springs: Array[Node3D] = [] ## water source index - 1 -> spring pool


## Builds the island a world recipe (state.world, see WorldGen) describes.
func build(world: Dictionary, seed_value: int) -> void:
	shape = IslandShape.new(world, seed_value)
	sites = WorkSites.new(shape)
	_look = BiomeLook.of(world)
	_snow_depth = BiomeLook.snow(world)
	_water_material.shader = WATER_SHADER
	_build_environment()
	_build_island(world, seed_value)
	herds.setup(shape, sites, seed_value)
	add_child(herds)
	_build_clouds(seed_value)
	_build_rain()
	camera_rig.fit(shape.radius)
	add_child(camera_rig)


## The tribe whose camp is drawn closest to a screen position, or "" if none is near.
func pick_tribe(screen_position: Vector2, max_distance: float = 110.0) -> String:
	var best := ""
	var best_distance := max_distance
	for tribe: String in _camps:
		var camp := _camps[tribe] as Settlement
		if camera_rig.camera.is_position_behind(camp.global_position):
			continue
		var distance := camera_rig.camera.unproject_position(camp.global_position).distance_to(screen_position)
		if distance < best_distance:
			best = tribe
			best_distance = distance
	return best


## The person whose figure is drawn under a screen position, or -1 if none is near.
func pick_person(screen_position: Vector2, max_distance: float = 20.0) -> int:
	var best := -1
	var best_distance := max_distance
	var camera := camera_rig.camera
	for tribe: String in _camps:
		var camp := _camps[tribe] as Settlement
		for id: int in camp.person_ids():
			var body := camp.figure(id)
			if body == null:
				continue
			var middle := body.global_position + Vector3(0.0, VillagerArt.HEIGHT * 0.5 * float(body.get_meta("growth", 1.0)), 0.0)
			if camera.is_position_behind(middle):
				continue
			var distance := camera.unproject_position(middle).distance_to(screen_position)
			if distance < best_distance:
				best = id
				best_distance = distance
	return best


## Rings the person being inspected and shows their name; -1 clears it.
func focus_person(id: int, label: String = "") -> void:
	_focused_person = id
	_focus_label = label


## Where a person's figure is now, or null if they aren't drawn.
func person_position(id: int) -> Variant:
	for tribe: String in _camps:
		var at: Variant = (_camps[tribe] as Settlement).person_position(id)
		if at != null:
			return at
	return null


func select_tribe(tribe: String) -> void:
	if _camps.has(_selected):
		(_camps[_selected] as Settlement).set_selected(false)
	_selected = tribe
	if _camps.has(tribe):
		(_camps[tribe] as Settlement).set_selected(true)


func selected_tribe() -> String:
	return _selected if _camps.has(_selected) else ""


func camp_position(tribe: String) -> Variant:
	return (_camps[tribe] as Settlement).global_position if _camps.has(tribe) else null


func sync(state: WorldState, delta: float) -> void:
	for i: int in state.tribe_count():
		var tribe := state.tribe_names[i]
		if not _camps.has(tribe):
			_add_camp(tribe)
	# Deaths are buried before the dead vanish from the camps.
	for event: Dictionary in state.events:
		if int(event["id"]) <= _last_event_id:
			continue
		_last_event_id = int(event["id"])
		var data: Dictionary = event["data"]
		if event["type"] == "death" and _camps.has(String(data.get("tribe", ""))):
			(_camps[String(data["tribe"])] as Settlement).bury(int(data["id"]), int(data.get("chief", 0)) == 1)
		if _wants_popup(event):
			_popups.push(event)
	for item: Dictionary in _popups.take(delta):
		_show_popup(item)
	var people := {} ## tribe -> {person id -> info}
	for tribe: String in state.tribe_names:
		people[tribe] = {}
	var chiefs := {}
	for t: int in state.tribe_count():
		chiefs[state.tribe_chiefs[t]] = true
	for p: int in state.person_ids.size():
		var tribe := state.person_tribes[p]
		if not people.has(tribe):
			continue
		var id := state.person_ids[p]
		(people[tribe] as Dictionary)[id] = {
			"female": People.is_female(state, p), "age": People.age(state, p), "chief": chiefs.has(id),
			"genome": state.person_genomes[p], "activity": People.activity(state, p), "job": state.person_jobs[p],
			"home": state.person_homes[p], "mother": state.person_mothers[p], "newborn": state.tick - state.person_born[p] < 20,
		}
	# People who moved to another tribe since last frame walk over from where they were.
	var arrivals := {}
	for tribe: String in people:
		for id: int in people[tribe]:
			var seen: Array = _last_seen.get(id, [])
			if not seen.is_empty() and seen[0] != tribe:
				arrivals[id] = seen[1]
	for tribe: String in people:
		var camp := _camps[tribe] as Settlement
		camp.sync(state, people[tribe], arrivals)
		camp.set_focus(_focused_person, _focus_label)
	_last_seen.clear()
	for tribe: String in people:
		var camp := _camps[tribe] as Settlement
		for id: int in people[tribe]:
			var at: Variant = camp.person_position(id)
			if at != null:
				_last_seen[id] = [tribe, at]
	for tribe: String in _camps.keys():
		if tribe not in state.tribe_names:
			(_camps[tribe] as Settlement).vanish()
			_camps.erase(tribe)
	for meeting: Dictionary in state.meetings:
		if int(meeting["id"]) <= _last_meeting_id:
			continue
		_last_meeting_id = int(meeting["id"])
		var a := state.index_of(int(meeting["a"]))
		var b := state.index_of(int(meeting["b"]))
		if a != -1 and b != -1 and state.person_tribes[a] == state.person_tribes[b] and _camps.has(state.person_tribes[a]):
			(_camps[state.person_tribes[a]] as Settlement).meet(int(meeting["a"]), int(meeting["b"]), String(meeting["kind"]))
	# Grass fades to straw during droughts and recovers after.
	var target_dryness := 1.0 if state.drought_months_left > 0 else 0.0
	_dryness = move_toward(_dryness, target_dryness, delta * 0.5)
	ToonMaterials.set_dryness(_dryness)
	# Cold islands whiten in the winter months and thaw in spring.
	var target_snow := _snow_depth if state.season() == "winter" else 0.0
	_snow = move_toward(_snow, target_snow, delta * 0.25)
	ToonMaterials.set_snow(_snow)
	atmosphere.update(state, delta)
	herds.sync(state, delta, _camps, camera_rig.camera)
	_clouds.rotation.y += delta * 0.01
	_rain.emitting = state.blessed_rain_months > 0
	_sync_water(state, delta)


## The pond sinks and shrinks as its level falls; spring pools shrink away to nothing.
func _sync_water(state: WorldState, delta: float) -> void:
	var pond_level := state.water_level[0]
	_pond.position.y = move_toward(_pond.position.y, IslandShape.WATER_LEVEL - (1.0 - pond_level) * 0.32, delta * 0.3)
	var pond_scale := lerpf(0.55, 1.0, pond_level)
	_pond.scale.x = move_toward(_pond.scale.x, pond_scale, delta * 0.3)
	_pond.scale.z = _pond.scale.x
	for w: int in range(1, state.water_names.size()):
		while _springs.size() < w:
			_springs.append(_build_spring(shape.spring_spot(_springs.size())))
			sites.springs.append(shape.spring_spot(_springs.size() - 1))
		var pool := _springs[w - 1].get_node("Pool") as Node3D
		var size := lerpf(0.15, 1.0, sqrt(state.water_level[w]))
		pool.scale = pool.scale.move_toward(Vector3(size, 1.0, size), delta * 0.3)
		pool.position.y = move_toward(pool.position.y, -0.1 - (1.0 - state.water_level[w]) * 0.22, delta * 0.2)


## Skip the pop-ups for events that happened before the view existed (e.g. after loading).
func mark_events_seen(state: WorldState) -> void:
	_last_event_id = state.next_event_id - 1
	_last_meeting_id = state.next_meeting_id - 1
	_popups.clear()
	atmosphere.reset()
	_snow = _snow_depth if state.season() == "winter" else 0.0


func _build_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.50, 0.36, 0.70)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.86, 0.56, 0.62)
	environment.fog_density = 0.002
	environment.fog_sky_affect = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	_sun.light_color = Color(1.0, 0.80, 0.62)
	_sun.light_energy = 0.95
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	_sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-35.0), 0.0)
	add_child(_sun)
	atmosphere = Atmosphere.new(environment, sky_material, _sun, _water_material)


## The island mesh in the biome's ground colors, the pond, then the biome's trees, rocks and
## undergrowth, as thick as the recipe says, kept off the camps and springs.
func _build_island(world: Dictionary, seed_value: int) -> void:
	var island := MeshInstance3D.new()
	island.mesh = IslandMesh.build(shape, seed_value, _look["ground"])
	island.material_override = ToonMaterials.get_material(Color.WHITE, 0.06, true)
	add_child(island)

	_pond = _water_disc(shape.pond_radius * 1.15)
	_pond.position = Vector3(shape.pond_center.x, IslandShape.WATER_LEVEL, shape.pond_center.y)
	add_child(_pond)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	var scrub := float(_look["scrub"])
	_scatter(rng, BiomeLook.count(world, "trees"), 0.5, func(at: Vector3) -> void:
		if rng.randf() < scrub:
			sites.bushes.append(_plant(Props.scrub(_look, rng), at, rng))
		else:
			sites.trees.append(_plant(Props.biome_tree(_look, rng), at, rng)))
	_scatter(rng, BiomeLook.count(world, "rocks"), 0.5, func(at: Vector3) -> void:
		sites.rocks.append(_plant(Props.biome_rock(_look, rng), at, rng)))
	_scatter(rng, BiomeLook.count(world, "undergrowth"), 0.3, func(at: Vector3) -> void:
		sites.bushes.append(_plant(Props.biome_plant(_look, rng), at, rng)))


## Picks up to `count` open spots (away from the edge, the water and the camps) and calls
## `place` with each.
func _scatter(rng: RandomNumberGenerator, count: int, margin: float, place: Callable) -> void:
	var placed := 0
	for attempt: int in count * 25:
		if placed >= count:
			break
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * shape.radius
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		# Only the fire's spot is kept clear: villages clear their own land as they grow.
		if not shape.is_buildable(x, z, margin) or shape.is_near_camp(x, z, 1.6):
			continue
		place.call(shape.surface_point(x, z))
		placed += 1


func _plant(prop: Node3D, at: Vector3, rng: RandomNumberGenerator) -> Node3D:
	prop.position = at
	prop.rotation.y = rng.randf() * TAU
	add_child(prop)
	return prop


func _water_disc(radius: float) -> MeshInstance3D:
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.01
	disc.radial_segments = 48
	water.mesh = disc
	water.material_override = _water_material
	return water


## A small pool ringed with stones.
func _build_spring(spot: Vector3) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spot)
	var spring := Node3D.new()
	spring.position = spot
	var pool := _water_disc(IslandShape.SPRING_RADIUS * 0.8)
	pool.name = "Pool"
	pool.position.y = -0.1
	spring.add_child(pool)
	for i: int in 9:
		var angle := TAU * i / 9.0
		var stone := Props.stone(rng)
		Props.recolor(stone, _look["foliage"])
		var x := cos(angle) * IslandShape.SPRING_RADIUS
		var z := sin(angle) * IslandShape.SPRING_RADIUS
		stone.position = Vector3(x, shape.height_at(spot.x + x, spot.z + z) - spot.y, z)
		stone.rotation.y = angle * 2.0
		spring.add_child(stone)
	add_child(spring)
	return spring


func _build_clouds(seed_value: int) -> void:
	add_child(_clouds)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	# A sea of clouds below the island, and a few drifting at its height, spread to its size.
	var reach := shape.radius / 10.0
	for i: int in CLOUD_SEA_COUNT:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(12.0, 42.0) * reach
		var cloud := Props.cloud(rng, rng.randf_range(2.2, 4.5))
		cloud.position = Vector3(cos(angle) * radius, rng.randf_range(-14.0, -9.0), sin(angle) * radius)
		_clouds.add_child(cloud)
	for i: int in 7:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(16.0, 30.0) * reach
		var cloud := Props.cloud(rng, rng.randf_range(1.0, 1.8))
		cloud.position = Vector3(cos(angle) * radius, rng.randf_range(-2.0, 4.0), sin(angle) * radius)
		_clouds.add_child(cloud)


func _build_rain() -> void:
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.35, 0.02)
	_rain.mesh = drop
	_rain.material_override = ToonMaterials.emissive(Color(0.7, 0.85, 1.0), Color(0.3, 0.45, 0.7))
	_rain.lifetime = 1.2
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(shape.radius, 0.5, shape.radius)
	_rain.amount = roundi(900 * pow(shape.radius / 10.0, 2.0))
	_rain.direction = Vector3.DOWN
	_rain.spread = 3.0
	_rain.initial_velocity_min = 9.0
	_rain.initial_velocity_max = 11.0
	_rain.gravity = Vector3.ZERO
	_rain.position.y = 9.0
	_rain.emitting = false
	add_child(_rain)


func _add_camp(tribe: String) -> void:
	var camp := Settlement.new()
	camp.position = shape.camp_slot(_next_slot)
	_next_slot += 1
	add_child(camp)
	camp.setup(tribe, shape, sites)
	_camps[tribe] = camp


func _wants_popup(event: Dictionary) -> bool:
	var type := String(event["type"])
	if type == "job":
		return int((event["data"] as Dictionary).get("first", 0)) == 1
	return type in POPUP_TYPES


## A short floating line over the person or camp an event (or a merged burst of them) is about.
func _show_popup(item: Dictionary) -> void:
	var event: Dictionary = item["event"]
	var merged := int(item["count"]) > 1
	var major := bool(item["major"])
	var text := EventPacer.burst_text(item, true) if merged else _popup_text(event)
	if text.is_empty():
		return
	var where := Vector3(0, 1, 0)
	var subject := -1 if merged else EventText.subject(event)
	var at: Variant = person_position(subject) if subject != -1 else null
	if at == null:
		at = camp_position(EventText.tribe_of(event))
	if at != null:
		where = at
	var label := Label3D.new()
	label.text = "%s %s" % [EventText.icon(event), text]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = UiStyle.font("strong") # the HUD's face, so world notes read as one with it
	label.font_size = 56 if major else 44
	label.outline_size = 14
	label.modulate = Color(1.0, 0.97, 0.9).lerp(EventText.color(event), 0.35)
	label.outline_modulate = ToonMaterials.INK
	label.pixel_size = 0.006 if major else 0.005
	label.no_depth_test = true
	# Events that land together stack instead of overlapping.
	if Engine.get_process_frames() != _popup_frame:
		_popup_frame = Engine.get_process_frames()
		_popups_this_frame.clear()
	var key := Vector3i(roundi(where.x * 2.0), 0, roundi(where.z * 2.0))
	var stacked := int(_popups_this_frame.get(key, 0))
	_popups_this_frame[key] = stacked + 1
	label.position = where + Vector3(0, (1.6 if major else 0.9) + stacked * 0.4, 0)
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 0.9, POPUP_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_SECONDS).set_delay(POPUP_SECONDS * 0.5)
	tween.chain().tween_callback(label.queue_free)


func _popup_text(event: Dictionary) -> String:
	var data: Dictionary = event["data"]
	match String(event["type"]):
		"birth":
			return "%s is born" % data.get("name", "")
		"death":
			return "%s (%d)" % [data.get("name", ""), int(data.get("age", 0))]
		"marriage":
			return "%s & %s" % [data.get("a_name", ""), data.get("b_name", "")]
		"proposal_refused":
			return "%s said no" % data.get("b_name", "")
		"adoption":
			return "%s finds a home" % data.get("name", "")
		"job":
			return "First %s!" % Jobs.name_of(String(data.get("job", "")))
		"discovery":
			return "%s!" % Knowledge.name_of(String(data.get("tech", "")))
		"tech_spread":
			return "%s learned" % Knowledge.name_of(String(data.get("tech", "")))
		"building_done":
			return "New %s" % Buildings.name_of(String(data.get("building", "")))
		"new_chief":
			return "%s leads" % data.get("name", "")
		"new_age":
			return "%s!" % data.get("name", "")
		"destiny":
			return String(data.get("name", ""))
		"revolution":
			return "Revolution!"
		"coup":
			return "Coup! %s rules" % data.get("name", "")
		"capture":
			return "%s buys power" % data.get("name", "")
		"uprising_crushed":
			return "Uprising crushed"
		"protests":
			return "Protests!"
		"new_dynasty":
			return "House %s" % data.get("house", "")
		"vassal":
			return "Kneels to the %s" % data.get("overlord", "")
	return EventText.text(event).trim_suffix(".")
