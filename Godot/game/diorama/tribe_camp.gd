class_name TribeCamp
extends Node3D
## One tribe on the island: a campfire, huts that grow with the population, and people
## wandering around the fire. Visual only: randomness here never touches the simulation.

const PEOPLE_PER_FIGURE := 6
const MAX_FIGURES := 14
const PEOPLE_PER_HUT := 14
const MAX_HUTS := 6
const WANDER_RADIUS := 1.6

var tribe_name: String
var shape: IslandShape
var tunic: Color
var roof: Color

var _rng := RandomNumberGenerator.new()
var _fire: Node3D
var _huts: Array[Node3D] = []
var _people: Array[Node3D] = []
var _targets: Array[Vector3] = []
var _phases := PackedFloat32Array()
var _selection_ring: MeshInstance3D


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
	var figure_count := clampi(ceili(float(population) / PEOPLE_PER_FIGURE), 1, MAX_FIGURES)
	while _people.size() < figure_count:
		_add_person()
	while _people.size() > figure_count:
		_people.pop_back().queue_free()
		_targets.pop_back()
		_phases.remove_at(_phases.size() - 1)


func set_selected(selected: bool) -> void:
	if selected and _selection_ring == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 2.0
		torus.outer_radius = 2.15
		torus.rings = 48
		_selection_ring = MeshInstance3D.new()
		_selection_ring.mesh = torus
		_selection_ring.material_override = ToonMaterials.emissive(Color(1.0, 0.92, 0.6), Color(1.0, 0.8, 0.4))
		_selection_ring.position.y = 0.15
		add_child(_selection_ring)
		_pop_in(_selection_ring)
	elif not selected and _selection_ring != null:
		_selection_ring.queue_free()
		_selection_ring = null


func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	if _selection_ring:
		_selection_ring.scale = Vector3.ONE * (1.0 + 0.03 * sin(time * 4.0))
	var flame := _fire.get_node("Flame") as Node3D
	var flicker := 0.85 + 0.15 * sin(time * 13.0 + _phases.size()) + 0.08 * sin(time * 23.0)
	flame.scale = Vector3(1.0, flicker, 1.0)
	(_fire.get_node("Light") as OmniLight3D).light_energy = 1.4 * flicker
	for i: int in _people.size():
		_walk(i, delta, time)


func _walk(i: int, delta: float, time: float) -> void:
	var person := _people[i]
	var to_target := _targets[i] - person.position
	to_target.y = 0.0
	if to_target.length() < 0.1:
		_targets[i] = _random_spot()
		return
	var step := to_target.normalized() * minf(0.6 * delta, to_target.length())
	person.position += step
	person.position.y = _ground(person.position)
	person.rotation.y = atan2(to_target.x, to_target.z)
	# Little hops with squash and stretch.
	var hop := absf(sin(time * 9.0 + _phases[i]))
	var body := person.get_node("Body") as Node3D
	body.position.y = 0.15 + hop * 0.06
	(person.get_node("Head") as Node3D).position.y = 0.38 + hop * 0.07
	body.scale = Vector3(1.0 + (1.0 - hop) * 0.12, 1.0 - (1.0 - hop) * 0.1, 1.0 + (1.0 - hop) * 0.12)


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


func _add_person() -> void:
	var person := Props.person(tunic)
	person.position = _random_spot()
	add_child(person)
	_people.append(person)
	_targets.append(_random_spot())
	_phases.append(_rng.randf() * TAU)
	_pop_in(person)


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


## Shrinks the camp away, then frees it.
func vanish() -> void:
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
