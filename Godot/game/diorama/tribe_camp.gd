class_name TribeCamp
extends Node3D
## One tribe on the island: a campfire, huts that grow with the population, and its citizens
## wandering around the fire, one figure each. Visual only: randomness here never touches the simulation.

const PEOPLE_PER_HUT := 14
const MAX_HUTS := 6
const WANDER_RADIUS := 1.6
const WALK_SPEED := 0.45 ## world units per second

var tribe_name: String
var shape: IslandShape
var tunic: Color
var roof: Color

var _rng := RandomNumberGenerator.new()
var _fire: Node3D
var _huts: Array[Node3D] = []
var _people: Dictionary = {} ## citizen id -> figure
var _targets: Dictionary = {} ## citizen id -> where the figure is walking
var _rests: Dictionary = {} ## citizen id -> seconds left standing before walking on
var _walking: Dictionary = {} ## citizen id -> 0 standing .. 1 walking, eased
var _chief_id := -1
var _selection_ring: MeshInstance3D
var _focus_ring: MeshInstance3D


func setup(name_of_tribe: String, island: IslandShape) -> void:
	tribe_name = name_of_tribe
	shape = island
	_rng.seed = hash(name_of_tribe)
	var hue := fposmod(float(hash(name_of_tribe) % 1000) / 1000.0, 1.0)
	tunic = Color.from_hsv(hue, 0.55, 0.85)
	roof = Props.THATCH.lerp(Color.from_hsv(hue, 0.5, 0.75), 0.25)
	_fire = Props.campfire()
	add_child(_fire)
	_pop_in(_fire)


func set_population(population: int) -> void:
	var hut_count := clampi(ceili(float(population) / PEOPLE_PER_HUT), 1, MAX_HUTS)
	while _huts.size() < hut_count:
		_add_hut()
	while _huts.size() > hut_count:
		_huts.pop_back().queue_free()


## Keeps one figure per citizen: newcomers pop in, the departed shrink away, and the chief
## wears the feathered headband.
func set_citizens(ids: PackedInt32Array, chief_id: int) -> void:
	for id: int in _people.keys():
		if id not in ids:
			_remove_person(id)
	for id: int in ids:
		if not _people.has(id):
			_add_person(id, id == chief_id)
	if chief_id != _chief_id:
		var old_chief := _chief_id
		_chief_id = chief_id
		for id: int in [old_chief, chief_id]:
			if _people.has(id):
				_replace_figure(id) # puts on (or takes off) the headdress


## The figure of a citizen, or null if this camp doesn't have them.
func figure(id: int) -> Node3D:
	return _people.get(id)


func citizen_ids() -> Array:
	return _people.keys()


## Puts a ring under the citizen being inspected, if they are in this camp. Cheap to call every frame.
func set_focus(id: int) -> void:
	var target: Node3D = _people.get(id)
	var holder: Node = _focus_ring.get_parent() if _focus_ring else null
	if holder == target:
		return
	if holder:
		holder.remove_child(_focus_ring)
	if target == null:
		return
	if _focus_ring == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.2
		torus.outer_radius = 0.26
		torus.rings = 24
		_focus_ring = MeshInstance3D.new()
		_focus_ring.mesh = torus
		_focus_ring.material_override = ToonMaterials.emissive(Color(1.0, 0.95, 0.7), Color(1.0, 0.85, 0.45))
		_focus_ring.position.y = 0.04
	target.add_child(_focus_ring)


func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	if _selection_ring:
		_selection_ring.scale = Vector3.ONE * (1.0 + 0.03 * sin(time * 4.0))
	var flame := _fire.get_node("Flame") as Node3D
	var flicker := 0.85 + 0.15 * sin(time * 13.0 + _huts.size()) + 0.08 * sin(time * 23.0)
	flame.scale = Vector3(1.0, flicker, 1.0)
	(_fire.get_node("Light") as OmniLight3D).light_energy = 1.4 * flicker
	for id: int in _people:
		_walk(id, delta)
	if _focus_ring and _focus_ring.get_parent():
		_focus_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(time * 5.0))


## Villagers stroll to a spot, stand a while, then pick another.
func _walk(id: int, delta: float) -> void:
	var person := _people[id] as Node3D
	var to_target: Vector3 = _targets[id] - person.position
	to_target.y = 0.0
	var moving := to_target.length() > 0.05 and float(_rests[id]) <= 0.0
	_walking[id] = move_toward(float(_walking[id]), 1.0 if moving else 0.0, delta * 3.0)
	VillagerArt.set_walking(person, float(_walking[id]))
	if float(_rests[id]) > 0.0:
		_rests[id] = float(_rests[id]) - delta
		return
	if not moving:
		_targets[id] = _random_spot()
		_rests[id] = _rng.randf_range(0.5, 4.0)
		return
	var step := to_target.normalized() * minf(WALK_SPEED * float(_walking[id]) * delta, to_target.length())
	person.position += step
	person.position.y = _ground(person.position)
	person.rotation.y = lerp_angle(person.rotation.y, atan2(to_target.x, to_target.z), minf(delta * 8.0, 1.0))


func _add_hut() -> void:
	var hut := Props.hut(roof)
	var angle := TAU * _huts.size() / MAX_HUTS + 0.4
	var radius := 1.0 + 0.18 * (_huts.size() % 2)
	hut.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	hut.position.y = _ground(hut.position)
	hut.rotation.y = -angle
	add_child(hut)
	_huts.append(hut)
	_pop_in(hut)


func _add_person(id: int, chief: bool) -> void:
	var person := _make_figure(id, chief)
	person.position = _random_spot()
	add_child(person)
	_people[id] = person
	_targets[id] = _random_spot()
	_rests[id] = _rng.randf_range(0.0, 3.0)
	_walking[id] = 0.0
	_pop_in(person)


## Each citizen always looks the same: their id picks build, hair and skin tone.
func _make_figure(id: int, chief: bool) -> Node3D:
	var looks := hash(id * 7919)
	var person := VillagerArt.make(
		posmod(id, VillagerArt.LOOKS.size()), chief, tunic,
		VillagerArt.HAIR_COLORS[posmod(looks, VillagerArt.HAIR_COLORS.size())],
		VillagerArt.SKIN_TONES[posmod(looks / 7, VillagerArt.SKIN_TONES.size())])
	VillagerArt.offset_time(person, _rng.randf() * 2.0)
	return person


func _replace_figure(id: int) -> void:
	var old := _people[id] as Node3D
	var person := _make_figure(id, id == _chief_id)
	person.transform = old.transform
	if _focus_ring and _focus_ring.get_parent() == old:
		old.remove_child(_focus_ring)
	add_child(person)
	_people[id] = person
	old.queue_free()


func _remove_person(id: int) -> void:
	var person := _people[id] as Node3D
	if _focus_ring and _focus_ring.get_parent() == person:
		person.remove_child(_focus_ring)
	_people.erase(id)
	_targets.erase(id)
	_rests.erase(id)
	_walking.erase(id)
	var tween := create_tween()
	tween.tween_property(person, "scale", Vector3.ONE * 0.01, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(person.queue_free)


func _random_spot() -> Vector3:
	var angle := _rng.randf() * TAU
	var radius := _rng.randf_range(0.4, WANDER_RADIUS)
	var spot := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	spot.y = _ground(spot)
	return spot


## Ground height in this camp's local space.
func _ground(local: Vector3) -> float:
	return shape.height_at(position.x + local.x, position.z + local.z) - position.y


func _pop_in(node: Node3D) -> void:
	var final_scale := node.scale
	node.scale = Vector3.ONE * 0.01
	create_tween().tween_property(node, "scale", final_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	# The focus ring lives outside the tree while nobody here is inspected.
	if what == NOTIFICATION_PREDELETE and _focus_ring and _focus_ring.get_parent() == null:
		_focus_ring.free()


## Shrinks the camp away, then frees it.
func vanish() -> void:
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
