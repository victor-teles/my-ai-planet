class_name Diorama
extends Node3D
## The world as a floating-island diorama. Reads the simulation each frame and keeps the
## view in step with it; never writes to the simulation.

const SKY_SHADER := preload("res://art/shaders/sky_dusk.gdshader")
const WATER_SHADER := preload("res://art/shaders/water.gdshader")
const TREE_COUNT := 70
const UNDERGROWTH_COUNT := 130 ## bushes, grass, flowers, mushrooms, fallen logs
const CLOUD_SEA_COUNT := 46
const POPUP_SECONDS := 3.0

var shape: IslandShape
var camera_rig := CameraRig.new()

var _camps: Dictionary = {} ## tribe name -> TribeCamp
var _slots_used: Dictionary = {} ## tribe name -> slot index
var _next_slot := 0
var _last_event_id := -1
var _dryness := 0.0
var _clouds := Node3D.new()
var _sun := DirectionalLight3D.new()
var _rain := CPUParticles3D.new()
var _selected := ""
var _focused_citizen := -1
var _popup_frame := -1 ## the frame the last pop-up appeared in
var _popups_this_frame: Dictionary = {} ## where -> how many pop-ups started there this frame
var _pond: MeshInstance3D
var _springs: Array[Node3D] = [] ## water source index - 1 -> spring pool


func build(seed_value: int) -> void:
	shape = IslandShape.new(seed_value)
	_build_environment()
	_build_island(seed_value)
	_build_clouds(seed_value)
	_build_rain()
	add_child(camera_rig)


## The tribe whose camp is drawn closest to a screen position, or "" if none is near.
func pick_tribe(screen_position: Vector2, max_distance: float = 90.0) -> String:
	var best := ""
	var best_distance := max_distance
	for tribe: String in _camps:
		var camp := _camps[tribe] as TribeCamp
		if camera_rig.camera.is_position_behind(camp.global_position):
			continue
		var distance := camera_rig.camera.unproject_position(camp.global_position).distance_to(screen_position)
		if distance < best_distance:
			best = tribe
			best_distance = distance
	return best


## The citizen whose figure is drawn under a screen position, or -1 if none is near.
func pick_citizen(screen_position: Vector2, max_distance: float = 22.0) -> int:
	var best := -1
	var best_distance := max_distance
	var camera := camera_rig.camera
	for tribe: String in _camps:
		var camp := _camps[tribe] as TribeCamp
		for id: int in camp.citizen_ids():
			var middle := camp.figure(id).global_position + Vector3(0.0, VillagerArt.HEIGHT * 0.5, 0.0)
			if camera.is_position_behind(middle):
				continue
			var distance := camera.unproject_position(middle).distance_to(screen_position)
			if distance < best_distance:
				best = id
				best_distance = distance
	return best


## Rings the citizen being inspected; -1 clears it.
func focus_citizen(id: int) -> void:
	_focused_citizen = id


func select_tribe(tribe: String) -> void:
	if _camps.has(_selected):
		(_camps[_selected] as TribeCamp).set_selected(false)
	_selected = tribe
	if _camps.has(tribe):
		(_camps[tribe] as TribeCamp).set_selected(true)


func selected_tribe() -> String:
	return _selected if _camps.has(_selected) else ""


func sync(state: WorldState, delta: float) -> void:
	var members := {} ## tribe name -> {citizen id -> {"female", "age", "chief"}}
	var chiefs := {}
	for tribe: String in state.tribe_names:
		members[tribe] = {}
		chiefs[tribe] = Citizens.chief(state, tribe)
	for c: int in state.citizen_ids.size():
		var tribe := state.citizen_tribes[c]
		if members.has(tribe):
			(members[tribe] as Dictionary)[state.citizen_ids[c]] = {
				"female": Citizens.is_female(state, c), "age": Citizens.age(state, c), "chief": chiefs[tribe] == c,
			}
	for i: int in state.tribe_count():
		var tribe := state.tribe_names[i]
		if not _camps.has(tribe):
			_add_camp(tribe)
		var camp := _camps[tribe] as TribeCamp
		camp.set_population(state.tribe_population[i])
		camp.set_citizens(members[tribe])
		camp.set_focus(_focused_citizen) # also follows a citizen into a new tribe after a split or merge
	for tribe: String in _camps.keys():
		if tribe not in state.tribe_names:
			(_camps[tribe] as TribeCamp).vanish()
			_camps.erase(tribe)
	for event: Dictionary in state.events:
		if int(event["id"]) > _last_event_id:
			_last_event_id = int(event["id"])
			_show_event(event)
	# Grass fades to straw during droughts and recovers after.
	var target_dryness := 1.0 if state.drought_months_left > 0 else 0.0
	_dryness = move_toward(_dryness, target_dryness, delta * 0.5)
	ToonMaterials.set_dryness(_dryness)
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
		var pool := _springs[w - 1].get_node("Pool") as Node3D
		var size := lerpf(0.15, 1.0, sqrt(state.water_level[w]))
		pool.scale = pool.scale.move_toward(Vector3(size, 1.0, size), delta * 0.3)
		pool.position.y = move_toward(pool.position.y, -0.1 - (1.0 - state.water_level[w]) * 0.22, delta * 0.2)


## Skip the pop-ups for events that happened before the view existed (e.g. after loading).
func mark_events_seen(state: WorldState) -> void:
	_last_event_id = state.next_event_id - 1


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


func _build_island(seed_value: int) -> void:
	var island := MeshInstance3D.new()
	island.mesh = IslandMesh.build(shape, seed_value)
	island.material_override = ToonMaterials.get_material(Color.WHITE, 0.06, true)
	add_child(island)

	_pond = _water_disc(IslandShape.POND_RADIUS * 1.15)
	_pond.position = Vector3(IslandShape.POND_CENTER.x, IslandShape.WATER_LEVEL, IslandShape.POND_CENTER.y)
	add_child(_pond)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	var placed := 0
	for attempt: int in 2000:
		if placed >= TREE_COUNT:
			break
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * IslandShape.RADIUS
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		if not shape.is_buildable(x, z, 0.5) or shape.is_near_camp(x, z, 2.4):
			continue
		var prop: Node3D
		var roll := rng.randf()
		if roll < 0.45:
			prop = Props.pine(rng)
		elif roll < 0.8:
			prop = Props.leafy_tree(rng)
		else:
			prop = Props.rock(rng)
		prop.position = shape.surface_point(x, z)
		prop.rotation.y = rng.randf() * TAU
		add_child(prop)
		placed += 1
	placed = 0
	for attempt: int in 3000:
		if placed >= UNDERGROWTH_COUNT:
			break
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * IslandShape.RADIUS
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		if not shape.is_buildable(x, z, 0.3) or shape.is_near_camp(x, z, 2.0):
			continue
		var plant := Props.undergrowth(rng)
		plant.position = shape.surface_point(x, z)
		plant.rotation.y = rng.randf() * TAU
		add_child(plant)
		placed += 1


func _water_disc(radius: float) -> MeshInstance3D:
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.01
	disc.radial_segments = 48
	water.mesh = disc
	var water_material := ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water.material_override = water_material
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
	# A sea of clouds below the island, and a few drifting at its height.
	for i: int in CLOUD_SEA_COUNT:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(12.0, 42.0)
		var cloud := Props.cloud(rng, rng.randf_range(2.2, 4.5))
		cloud.position = Vector3(cos(angle) * radius, rng.randf_range(-14.0, -9.0), sin(angle) * radius)
		_clouds.add_child(cloud)
	for i: int in 7:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(16.0, 30.0)
		var cloud := Props.cloud(rng, rng.randf_range(1.0, 1.8))
		cloud.position = Vector3(cos(angle) * radius, rng.randf_range(-2.0, 4.0), sin(angle) * radius)
		_clouds.add_child(cloud)


func _build_rain() -> void:
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.35, 0.02)
	_rain.mesh = drop
	_rain.material_override = ToonMaterials.emissive(Color(0.7, 0.85, 1.0), Color(0.3, 0.45, 0.7))
	_rain.amount = 900
	_rain.lifetime = 1.2
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(IslandShape.RADIUS, 0.5, IslandShape.RADIUS)
	_rain.direction = Vector3.DOWN
	_rain.spread = 3.0
	_rain.initial_velocity_min = 9.0
	_rain.initial_velocity_max = 11.0
	_rain.gravity = Vector3.ZERO
	_rain.position.y = 9.0
	_rain.emitting = false
	add_child(_rain)


func _add_camp(tribe: String) -> void:
	var camp := TribeCamp.new()
	camp.position = shape.camp_slot(_next_slot)
	_slots_used[tribe] = _next_slot
	_next_slot += 1
	add_child(camp)
	camp.setup(tribe, shape)
	_camps[tribe] = camp


func _show_event(event: Dictionary) -> void:
	var data: Dictionary = event["data"]
	var text := ""
	var where := Vector3.ZERO
	match String(event["type"]):
		"tribe_split":
			text = "The %s leave the %s!" % [data["to"], data["from"]]
			where = _camp_position(String(data["to"]))
		"famine":
			text = "Hunger among the %s" % data["tribe"]
			where = _camp_position(String(data["tribe"]))
		"tribe_extinct":
			text = "The %s are gone" % data["tribe"]
		"drought_started":
			text = "The rains fail..."
		"drought_ended":
			text = "The rains return"
		"dilemma":
			text = "The god decides: %s" % data["choice"]
		"war":
			text = "War! The %s defeat the %s" % [data["winner"], data["loser"]]
			where = _camp_position(String(data["loser"]))
		"tribes_merged":
			text = "The %s join the %s" % [data["from"], data["into"]]
			where = _camp_position(String(data["into"]))
		"new_chief": # follows the old chief's death, so one pop-up tells both
			text = "%s now leads the %s" % [data["name"], data["tribe"]]
			where = _camp_position(String(data["tribe"]))
		"tribe_moved":
			text = "The %s go to drink from %s" % [data["tribe"], data["water"]]
			where = _camp_position(String(data["tribe"]))
		"water_low":
			text = "%s is running low" % String(data["water"]).capitalize()
		"miracle":
			match String(data["miracle"]):
				"rain":
					text = "The sky opens: rain!"
				"harvest":
					text = "A bountiful harvest for the %s" % data["tribe"]
					where = _camp_position(String(data["tribe"]))
				"drought":
					text = "The god withholds the rain"
				"plague":
					text = "Sickness among the %s" % data["tribe"]
					where = _camp_position(String(data["tribe"]))
		_:
			return
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.outline_size = 14
	label.outline_modulate = ToonMaterials.INK
	label.pixel_size = 0.006
	label.no_depth_test = true
	# Events that land together (a chief dies, another takes over) stack instead of overlapping.
	if Engine.get_process_frames() != _popup_frame:
		_popup_frame = Engine.get_process_frames()
		_popups_this_frame.clear()
	var stacked := int(_popups_this_frame.get(where, 0))
	_popups_this_frame[where] = stacked + 1
	label.position = where + Vector3(0, 2.2 + stacked * 0.45, 0)
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 1.2, POPUP_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_SECONDS).set_delay(POPUP_SECONDS * 0.5)
	tween.chain().tween_callback(label.queue_free)


func _camp_position(tribe: String) -> Vector3:
	return (_camps[tribe] as TribeCamp).position if _camps.has(tribe) else Vector3(0, 1, 0)
