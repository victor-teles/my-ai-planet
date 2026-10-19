class_name Herds
extends Node3D
## The island's animals as the diorama draws them. Every frame it reads the living animals from
## WorldState (never writing to it), adds the newborn, lets the dead fall, and moves the rest as
## herds on the shared Steering module: they graze with the head down and drift across the
## grass together (cohesion, separation, alignment), look up when people come within the
## distance their wariness gene allows, and bolt at a run when they come closer. The young keep
## to their mothers. Wolves and big cats trot as a pack, rest, and now and then chase a herd.
## Far and off-screen animals update less often (level of detail).

const SPREAD := 0.55 ## how far a herd's animals graze from its middle, per sqrt(member)
const CAMP_CLEARANCE := 1.4 ## added to a camp's radius when herds pick grazing grounds
const THREAT_SECONDS := 0.2 ## how often herds look around
const DYING_SECONDS := 2.4
## Flight distance in world units: the boldest animal lets people this close, the warinest this.
const FLIGHT_NEAR := 0.9
const FLIGHT_FAR := 2.6
const HUNTER_REACH := 0.6 ## a hunter (or a wolf, for prey) is noticed this much further off
const ALERT_SHARE := 1.6 ## heads come up at this many flight distances
## Gaits in world units per second (a villager walks at 0.42).
const GAITS := {
	"deer": {"walk": 0.26, "run": 1.5}, "boar": {"walk": 0.2, "run": 1.0}, "wolf": {"walk": 0.3, "trot": 0.5, "run": 1.6},
	"horse": {"walk": 0.3, "run": 1.7}, "goat": {"walk": 0.22, "run": 1.2}, "cat": {"walk": 0.24, "trot": 0.4, "run": 1.7},
	"bear": {"walk": 0.22, "run": 1.0}, "sheep": {"walk": 0.22, "run": 1.1},
}
const DEFAULT_GAIT := {"walk": 0.22, "run": 1.0}
## Clip rates: world units a model of height 1 covers per second at rate 1 when walking or running.
const WALK_STRIDE := 0.7
const RUN_STRIDE := 3.2
## Level of detail: frames between full updates (steering and animation) when seen close up,
## at middle distance, far off, and unseen. In between, moving animals glide on.
const NEAR := 10.0
const FAR := 20.0
const LOD_FRAMES: Array[int] = [1, 2, 5, 12]
## Rocks and trunks within this reach of a herd are steered around, the nearest MAX_PROPS.
const ROCK_REACH := 4.0
const ROCK_RADIUS := 0.45
const TRUNK_RADIUS := 0.2
const MAX_PROPS := 14
const INK_DISTANCE := 26.0 ## past this (for a deer-sized animal) the ink line is under a pixel
const SHUFFLE := 0.6 ## a grazer this close to its spot steps there directly


## One animal on screen.
class Beast:
	extends RefCounted
	var id := -1
	var species := ""
	var node: Node3D
	var mover: Dictionary = {}
	var herd: Herd
	var mother := -1
	var young := false
	var female := false
	var model := ""
	var height := 0.4
	var wariness := 0.5
	var speed := 0.5
	var offset := Vector3.ZERO ## where it grazes, from the herd's middle
	var timer := 0.0 ## until it shifts to a new patch of grass
	var looking := 0.0 ## seconds left of a look around while grazing
	var doing := "graze" ## graze, walk, alert, flee, follow, trot, chase, rest, dying
	var dying := 0.0
	var pending := 0.0 ## time not yet stepped (level of detail)
	var slot := 0
	var seen := true
	var settled := false
	var inks: Array[Node3D] = [] ## its ink outline hulls, hidden when too far off to show
	var inked := true
	var lod := 0 ## 0 close up, 1 middle distance, 2 far, 3 unseen
	var since := 0.0 ## seconds since its last full update, while it glides


## Animals that keep together: a herd, a pack, or a lone bear.
class Herd:
	extends RefCounted
	var key := ""
	var species := ""
	var hunter := false ## wolves and big cats
	var members: Array[Beast] = []
	var anchor := Vector3.ZERO ## the middle they gather around (moves smoothly)
	var goal := Vector3.ZERO ## where the anchor is heading
	var mode := "graze" ## graze, move, alert, flee; packs: rest, trot, chase
	var timer := 0.0
	var threat := Vector3.ZERO
	var threat_distance := INF
	var threat_kind := "" ## "people", "hunters" or a hunting species id
	var prey: Herd ## the herd a pack is chasing
	var calm := 0.0 ## seconds since a flight during which only a closer threat sets it off again
	var obstacles: Array = []
	var obstacles_age := INF


var shape: IslandShape
var sites: WorkSites
var _rng := RandomNumberGenerator.new()
var _beasts: Dictionary = {} ## animal id -> Beast
var _herds: Array[Herd] = []
var _dying: Array[Beast] = []
var _stamp := "" ## what the animal list looked like last time it was read
var _month := -1
var _threat_clock := 0.0
var _frame := 0
var _camps: Array[Dictionary] = [] ## {"center": Vector3, "radius": float}
var _people: Array[Vector4] = [] ## x, z, reach bonus, unused
var _focus_ring: MeshInstance3D
var _focused := -1
var _next_slot := 0


func setup(island: IslandShape, work_sites: WorkSites, seed_value: int) -> void:
	shape = island
	sites = work_sites
	_rng.seed = seed_value + 77


## Keeps the drawn animals in step with the simulation and moves them. camps: tribe -> Settlement.
func sync(state: WorldState, delta: float, camps: Dictionary, camera: Camera3D) -> void:
	_frame += 1
	var stamp := "%d|%d" % [state.animal_ids.size(), state.next_animal_id]
	if stamp != _stamp or state.month() != _month:
		_read_camps(state, camps)
		_refresh(state)
		_stamp = stamp
		_month = state.month()
	_threat_clock -= delta
	if _threat_clock <= 0.0:
		_threat_clock = THREAT_SECONDS
		_read_camps(state, camps)
		_read_people(state, camps)
		for herd: Herd in _herds:
			_look_around(herd)
	for herd: Herd in _herds:
		_lead(herd, delta)
	var eye := camera.global_position if camera and camera.is_inside_tree() else Vector3(0, 20, 20)
	for herd: Herd in _herds:
		var mates: Array = []
		for beast: Beast in herd.members:
			mates.append(beast.mover)
		for beast: Beast in herd.members:
			beast.pending += delta
			var interval := _interval(beast, camera, eye)
			if (_frame + beast.slot) % interval != 0:
				_glide(beast, delta)
				continue
			_step(beast, minf(beast.pending, 0.5), mates)
			beast.pending = 0.0
	for beast: Beast in _dying.duplicate():
		_fall(beast, delta)
	if _focus_ring and _focus_ring.get_parent():
		_focus_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() / 200.0))


## The animal drawn under a screen position, or -1.
func pick(camera: Camera3D, screen_position: Vector2, max_distance: float = 22.0) -> int:
	var best := -1
	var best_distance := max_distance
	for beast: Beast in _beasts.values():
		var middle := beast.node.global_position + Vector3(0.0, beast.height * 0.45, 0.0)
		if camera.is_position_behind(middle):
			continue
		var distance := camera.unproject_position(middle).distance_to(screen_position)
		if distance < best_distance:
			best = beast.id
			best_distance = distance
	return best


func position_of(id: int) -> Variant:
	var beast: Beast = _beasts.get(id)
	if beast == null:
		return null
	return beast.node.global_position if beast.node.is_inside_tree() else beast.node.position


## What an animal is doing, in a few words for its panel ("grazing", "fleeing from the hunters").
func activity_of(id: int) -> String:
	var beast: Beast = _beasts.get(id)
	if beast == null:
		return ""
	var herd := beast.herd
	match beast.doing:
		"follow":
			return "keeping close to its mother"
		"flee":
			return "fleeing from %s" % _threat_words(herd)
		"alert":
			return "watching %s" % _threat_words(herd)
		"chase":
			var prey := herd.prey.species if herd.prey else ""
			return "chasing the " + plural(String(Species.get_species(prey).get("name", "herd"))) if not prey.is_empty() else "on the hunt"
		"trot":
			return "trotting with the pack" if herd.members.size() > 1 else "roaming"
		"rest":
			return "resting with the pack" if herd.members.size() > 1 else "resting"
		"walk":
			return "moving with the herd" if herd.members.size() > 1 else "wandering"
	return "grazing" if Species.get_species(beast.species).get("diet", "") != "predator" else "resting"


## Rings the animal being inspected; -1 clears it.
func focus(id: int) -> void:
	_focused = id
	if _focus_ring == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.2
		torus.outer_radius = 0.25
		torus.rings = 24
		_focus_ring = MeshInstance3D.new()
		_focus_ring.mesh = torus
		_focus_ring.material_override = ToonMaterials.emissive(Color(1.0, 0.95, 0.7), Color(1.0, 0.85, 0.45))
	var beast: Beast = _beasts.get(id)
	var target: Node3D = beast.node if beast else null
	if _focus_ring.get_parent() != target:
		if _focus_ring.get_parent():
			_focus_ring.get_parent().remove_child(_focus_ring)
		if target:
			target.add_child(_focus_ring)
	if beast:
		_focus_ring.position.y = 0.03
		var reach := maxf(beast.height * 1.4, 0.3) / 0.45
		_focus_ring.scale = Vector3.ONE * reach / maxf(beast.node.scale.x, 0.01)


func count() -> int:
	return _beasts.size()


# --- Reading the simulation ---------------------------------------------------------

func _refresh(state: WorldState) -> void:
	var alive := {}
	for i: int in state.animal_ids.size():
		alive[state.animal_ids[i]] = i
	for id: int in _beasts.keys():
		if not alive.has(id):
			_lose(_beasts[id])
	var fresh: Array[int] = []
	for id: int in alive:
		if not _beasts.has(id):
			fresh.append(id)
	fresh.sort()
	# Adults first, so the young can find a mother among them.
	fresh.sort_custom(func(a: int, b: int) -> bool:
		return state.animal_born[alive[a]] < state.animal_born[alive[b]])
	for id: int in fresh:
		_spawn(state, int(alive[id]))
	# Growing up: the young grow, and a young male's antlers come in.
	for id: int in alive:
		var beast: Beast = _beasts[id]
		var i := int(alive[id])
		var age := state.tick - state.animal_born[i]
		var looks := AnimalArt.appearance_of(beast.species, state.animal_genomes[i], id, beast.female, age)
		var young := age < AnimalSystem.ADULT_YEARS * WorldState.DAYS_PER_YEAR
		if String(looks["model"]) != beast.model or (beast.young and not young):
			_rebuild(beast, looks)
		elif not is_equal_approx(float(looks["height"]), beast.height):
			beast.node.scale = Vector3.ONE * float(looks["height"]) / float(beast.node.get_meta("height"))
			beast.height = float(looks["height"])
		beast.young = young
		if not young:
			beast.mother = -1


func _spawn(state: WorldState, i: int) -> void:
	var table := Species.animal_table()
	var beast := Beast.new()
	beast.id = state.animal_ids[i]
	beast.species = state.animal_species[i]
	beast.female = state.animal_sex[i] == "f"
	var age := state.tick - state.animal_born[i]
	beast.young = age < AnimalSystem.ADULT_YEARS * WorldState.DAYS_PER_YEAR
	beast.wariness = Genetics.express(state.animal_genomes[i], "wariness", table)
	beast.speed = Genetics.express(state.animal_genomes[i], "speed", table)
	beast.slot = _next_slot
	_next_slot += 1
	var looks := AnimalArt.appearance_of(beast.species, state.animal_genomes[i], beast.id, beast.female, age)
	beast.node = AnimalArt.make(looks)
	beast.model = String(looks["model"])
	beast.height = float(looks["height"])
	beast.inks = AnimalArt.inks_of(beast.node)
	add_child(beast.node)
	if beast.young:
		beast.mother = _mother_for(beast)
	var herd := _herd_for(beast)
	beast.herd = herd
	herd.members.append(beast)
	beast.offset = _graze_offset(herd)
	var at := herd.anchor + beast.offset
	var mother: Beast = _beasts.get(beast.mother)
	if mother:
		at = mother.node.position + Vector3(_rng.randf_range(-0.2, 0.2), 0.0, _rng.randf_range(-0.2, 0.2))
	at = _on_land(at, herd.anchor)
	beast.node.position = shape.surface_point(at.x, at.z)
	var heading := _rng.randf() * TAU
	beast.node.rotation.y = heading
	var gait: Dictionary = GAITS.get(beast.species, DEFAULT_GAIT)
	beast.mover = Steering.mover(beast.node.position, heading, 0.0, beast.height * 0.3, float(gait["walk"]),
		1.2, 3.0, beast.height * 0.8, beast.id)
	beast.timer = _rng.randf_range(2.0, 10.0)
	AnimalArt.play(beast.node, "graze")
	AnimalArt.advance(beast.node, _rng.randf_range(0.0, 3.0))
	_beasts[beast.id] = beast


func _rebuild(beast: Beast, looks: Dictionary) -> void:
	var old := beast.node
	beast.node = AnimalArt.make(looks)
	beast.node.transform = old.transform
	beast.node.scale = Vector3.ONE
	beast.model = String(looks["model"])
	beast.height = float(looks["height"])
	beast.inks = AnimalArt.inks_of(beast.node)
	beast.inked = true
	add_child(beast.node)
	if _focus_ring and _focus_ring.get_parent() == old:
		old.remove_child(_focus_ring)
		beast.node.add_child(_focus_ring)
	old.queue_free()
	AnimalArt.play(beast.node, "graze")


## An animal gone from the simulation falls where it stands (or vanishes if nobody sees it).
func _lose(beast: Beast) -> void:
	_beasts.erase(beast.id)
	beast.herd.members.erase(beast)
	if beast.herd.members.is_empty():
		_herds.erase(beast.herd)
		for herd: Herd in _herds:
			if herd.prey == beast.herd:
				herd.prey = null
	for other: Beast in _beasts.values():
		if other.mother == beast.id:
			other.mother = -1
	if not beast.seen:
		beast.node.queue_free()
		return
	beast.doing = "dying"
	if AnimalArt.has_clip(beast.node, "death"):
		AnimalArt.play(beast.node, "death")
	_dying.append(beast)


func _fall(beast: Beast, delta: float) -> void:
	beast.dying += delta
	var model := beast.node.get_node("Model") as Node3D
	if AnimalArt.has_clip(beast.node, "death"):
		AnimalArt.advance(beast.node, delta)
	else:
		model.rotation.z = lerpf(0.0, PI * 0.5, clampf(beast.dying / 0.6, 0.0, 1.0))
	if beast.dying > DYING_SECONDS * 0.6:
		beast.node.position.y -= delta * beast.height * 0.6
	if beast.dying > DYING_SECONDS:
		_dying.erase(beast)
		if _focus_ring and _focus_ring.get_parent() == beast.node:
			beast.node.remove_child(_focus_ring)
		beast.node.queue_free()


## An adult female of the same species with the fewest young at heel.
func _mother_for(young: Beast) -> int:
	var best := -1
	var best_load := 1 << 20
	for other: Beast in _beasts.values():
		if other.species != young.species or not other.female or other.young:
			continue
		var load := 0
		for kid: Beast in _beasts.values():
			if kid.mother == other.id:
				load += 1
		if load < best_load:
			best = other.id
			best_load = load
	return best


## The mother's herd, else the smallest herd of the species with room, else a new one.
func _herd_for(beast: Beast) -> Herd:
	var mother: Beast = _beasts.get(beast.mother)
	if mother:
		return mother.herd
	var size := maxi(int(Species.get_species(beast.species).get("herd", 6)), 1)
	var best: Herd = null
	for herd: Herd in _herds:
		if herd.species != beast.species or herd.members.size() >= size:
			continue
		if best == null or herd.members.size() < best.members.size():
			best = herd
	if best:
		return best
	var herd := Herd.new()
	herd.species = beast.species
	herd.key = "%s:%d" % [beast.species, _herds.size()]
	herd.hunter = beast.species in AnimalSystem.HUNTERS
	herd.anchor = _spot(_island_point(), shape.radius, Vector3.INF, 0.0)
	herd.goal = herd.anchor
	herd.mode = "rest" if herd.hunter else "graze"
	herd.timer = _rng.randf_range(4.0, 16.0)
	_herds.append(herd)
	return herd


## Camps the herds keep clear of: their middles and a radius that grows with the village.
func _read_camps(state: WorldState, camps: Dictionary) -> void:
	_camps.clear()
	for tribe: String in camps:
		var camp := camps[tribe] as Node3D
		var built := state.buildings_of(tribe).size()
		var rings := Settlement.RING_RADII
		var ring := 0 if built <= 6 else (1 if built <= 14 else (2 if built <= 24 else 3))
		_camps.append({"center": camp.position, "radius": rings[ring] + 0.5})


## Where people are, and who among them hunts.
func _read_people(state: WorldState, camps: Dictionary) -> void:
	_people.clear()
	for tribe: String in camps:
		var camp := camps[tribe] as Settlement
		for id: Variant in camp.person_ids():
			var at: Variant = camp.person_position(int(id))
			if at == null:
				continue
			var spot := at as Vector3
			var p := state.index_of(int(id))
			var hunter := p != -1 and state.person_jobs[p] == "hunter"
			_people.append(Vector4(spot.x, spot.z, HUNTER_REACH if hunter else 0.0, 1.0 if hunter else 0.0))


# --- Herds --------------------------------------------------------------------------

## The nearest danger: people (hunters count as nearer), and for prey, a hunting pack.
func _look_around(herd: Herd) -> void:
	var middle := _middle(herd)
	herd.threat_distance = INF
	herd.threat_kind = ""
	for person: Vector4 in _people:
		var distance := Vector2(person.x - middle.x, person.y - middle.z).length() - person.z
		if distance < herd.threat_distance:
			herd.threat_distance = distance
			herd.threat = Vector3(person.x, 0.0, person.y)
			herd.threat_kind = "hunters" if person.w > 0.0 else "people"
	if herd.hunter:
		return
	for other: Herd in _herds:
		if not other.hunter or other.members.is_empty():
			continue
		var at := _middle(other)
		# A resting pack is watched, a hunting one fled.
		var distance := Vector2(at.x - middle.x, at.z - middle.z).length() + 1.2
		if other.mode == "chase" and other.prey == herd:
			distance -= 1.2 + HUNTER_REACH + 1.5
		if distance < herd.threat_distance:
			herd.threat_distance = distance
			herd.threat = at
			herd.threat_kind = other.species


func _lead(herd: Herd, delta: float) -> void:
	if herd.members.is_empty():
		return
	herd.timer -= delta
	herd.obstacles_age += delta
	if herd.obstacles_age > 1.0:
		herd.obstacles_age = 0.0
		herd.obstacles = _obstacles_near(herd.anchor)
	herd.calm -= delta
	var flight := _flight(herd)
	if herd.calm > 0.0:
		flight *= 0.5 # just got away: it takes a closer threat to set them off again
	var gait: Dictionary = GAITS.get(herd.species, DEFAULT_GAIT)
	# Danger first: bolt away from it, or stop and watch.
	if herd.mode != "flee" and herd.threat_distance < flight and not (herd.hunter and herd.mode == "chase"):
		var away := _middle(herd) - herd.threat
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
		herd.goal = _spot(_middle(herd) + away * _rng.randf_range(2.6, 4.0), 1.4, herd.threat, flight * 1.5)
		herd.anchor = herd.goal
		herd.mode = "flee"
		herd.timer = _rng.randf_range(3.5, 5.0)
		for beast: Beast in herd.members:
			beast.offset = _graze_offset(herd) * 0.7
		return
	match herd.mode:
		"flee":
			if herd.timer <= 0.0:
				herd.mode = "rest" if herd.hunter else "graze"
				herd.timer = _rng.randf_range(6.0, 14.0)
				herd.calm = _rng.randf_range(8.0, 14.0)
		"alert", "graze", "rest":
			if herd.threat_distance < flight * ALERT_SHARE:
				herd.mode = "alert"
				herd.timer = maxf(herd.timer, 1.5)
			elif herd.mode == "alert" and herd.timer <= 0.0:
				herd.mode = "rest" if herd.hunter else "graze"
				herd.timer = _rng.randf_range(4.0, 10.0)
			elif herd.timer <= 0.0:
				var prey := _prey_for(herd) if herd.hunter else null
				if prey and _rng.randf() < 0.5:
					herd.mode = "chase"
					herd.prey = prey
					herd.timer = _rng.randf_range(4.5, 7.0)
				else:
					herd.goal = _spot(herd.anchor, 4.0, Vector3.INF, 0.0)
					herd.mode = "trot" if herd.hunter else "move"
					herd.timer = 30.0
		"move", "trot":
			var pace := float(gait.get("trot", gait["walk"])) if herd.mode == "trot" else float(gait["walk"]) * 0.8
			herd.anchor = herd.anchor.move_toward(herd.goal, pace * delta)
			if herd.anchor.distance_to(herd.goal) < 0.05 or herd.timer <= 0.0:
				herd.mode = "rest" if herd.hunter else "graze"
				herd.timer = _rng.randf_range(10.0, 24.0) if not herd.hunter else _rng.randf_range(6.0, 12.0)
				for beast: Beast in herd.members:
					beast.offset = _graze_offset(herd)
		"chase":
			if herd.prey == null or herd.prey.members.is_empty() or herd.timer <= 0.0:
				herd.prey = null
				herd.mode = "rest"
				herd.timer = _rng.randf_range(8.0, 16.0)
				herd.goal = _spot(herd.anchor, 2.0, Vector3.INF, 0.0)
				herd.anchor = herd.goal
			else:
				herd.anchor = _middle(herd.prey)
				herd.goal = herd.anchor


## A prey herd within reach of a pack, or null.
func _prey_for(pack: Herd) -> Herd:
	var middle := _middle(pack)
	var best: Herd = null
	var best_distance := 9.0
	for herd: Herd in _herds:
		if herd.hunter or herd.members.is_empty():
			continue
		if not Species.get_species(herd.species).get("gives", []).has("meat"):
			continue
		var distance := _middle(herd).distance_to(middle)
		if distance < best_distance:
			best = herd
			best_distance = distance
	return best


## The warinest animal sets the herd's flight distance; the rest follow its lead.
func _flight(herd: Herd) -> float:
	var wary := 0.0
	for beast: Beast in herd.members:
		wary = maxf(wary, beast.wariness)
	return lerpf(FLIGHT_NEAR, FLIGHT_FAR, wary)


func _middle(herd: Herd) -> Vector3:
	if herd.members.is_empty():
		return herd.anchor
	var sum := Vector3.ZERO
	for beast: Beast in herd.members:
		sum += beast.node.position
	sum /= float(herd.members.size())
	sum.y = 0.0
	return sum


func _threat_words(herd: Herd) -> String:
	match herd.threat_kind:
		"hunters":
			return "the hunters"
		"people", "":
			return "the people nearby"
	return "the " + plural(String(Species.get_species(herd.threat_kind).get("name", "wolf")))


## "wolves", "big cats", "deer": a species name for many of them, in lower case.
static func plural(species_name: String) -> String:
	var name := species_name.to_lower()
	if name.ends_with("deer") or name.ends_with("sheep"):
		return name
	if name.ends_with("f"):
		return name.left(-1) + "ves"
	return name + "s"


# --- Animals ------------------------------------------------------------------------

func _interval(beast: Beast, camera: Camera3D, eye: Vector3) -> int:
	if camera == null or not camera.is_inside_tree():
		# Headless (tests): full steering every frame, never animated.
		beast.seen = false
		beast.lod = 0
		return LOD_FRAMES[0]
	var at := beast.node.position + Vector3(0.0, beast.height * 0.5, 0.0)
	beast.seen = camera.is_position_in_frustum(at)
	if not beast.seen:
		beast.lod = 3
		return LOD_FRAMES[3]
	var distance := eye.distance_to(at)
	var inked := distance < INK_DISTANCE * maxf(beast.height / 0.5, 0.5)
	if inked != beast.inked:
		beast.inked = inked
		for ink: Node3D in beast.inks:
			ink.visible = inked
	beast.lod = 0 if distance < NEAR else (1 if distance < FAR else 2)
	return LOD_FRAMES[beast.lod]


func _step(beast: Beast, delta: float, mates: Array) -> void:
	var herd := beast.herd
	var gait: Dictionary = GAITS.get(beast.species, DEFAULT_GAIT)
	var quick := lerpf(0.88, 1.12, beast.speed)
	var walk := float(gait["walk"]) * quick
	var run := float(gait["run"]) * quick
	var target := herd.anchor + beast.offset
	var pace := walk
	var settle := 0.15
	var mother: Beast = _beasts.get(beast.mother) if beast.young else null
	match herd.mode:
		"flee", "chase":
			pace = run
			settle = 0.3
			beast.doing = herd.mode
		"move":
			pace = walk
			beast.doing = "walk"
		"trot":
			pace = float(gait.get("trot", gait["walk"])) * quick
			beast.doing = "trot"
		"alert":
			beast.doing = "alert" if herd.threat_distance < lerpf(FLIGHT_NEAR, FLIGHT_FAR, beast.wariness) * ALERT_SHARE else "graze"
		"rest":
			beast.doing = "rest"
		_:
			beast.doing = "graze"
	if mother and mother.node:
		# The young keep to their mother's flank, a little behind her.
		var back := Vector3(0.18 * (1.0 if beast.slot % 2 == 0 else -1.0), 0.0, -0.22).rotated(Vector3.UP, mother.node.rotation.y)
		target = mother.node.position + back * (mother.height / 0.5)
		pace = maxf(pace, Vector3(mother.mover.get("velocity", Vector3.ZERO)).length() * 1.15)
		if herd.mode not in ["flee", "chase"]:
			beast.doing = "follow" if mother.doing != "graze" else "graze"
	# A grazer shifts to fresh grass now and then.
	beast.timer -= delta
	if beast.timer <= 0.0 and herd.mode in ["graze", "rest"]:
		beast.timer = _rng.randf_range(5.0, 14.0)
		beast.offset = _graze_offset(herd)
		if _rng.randf() < 0.35:
			beast.looking = _rng.randf_range(1.0, 2.5)
	beast.looking -= delta
	var away := _xz(target) - _xz(beast.mover.position)
	# Once it has arrived it stays put until its spot is well away: herd mates jostling for
	# room do not keep a grazing animal shuffling.
	if away.length() > settle * 3.0 or herd.mode in ["flee", "chase", "move", "trot"]:
		beast.settled = false
	elif away.length() <= settle:
		beast.settled = true
	var moving := not beast.settled
	beast.mover["max_speed"] = pace
	beast.mover["max_acceleration"] = pace * (2.4 if herd.mode in ["flee", "chase"] else 1.6)
	var speed_now := 0.0
	var calm := herd.mode in ["graze", "rest", "alert"]
	if moving and ((calm and away.length() < SHUFFLE) or beast.lod >= 2):
		# A step or two to fresh grass, or an animal too far off to see the difference: it walks
		# straight there, without the full steering.
		speed_now = _walk_straight(beast, away, walk * 0.6 if calm else pace, delta, settle)
		var to := beast.mover.position as Vector3
		if not shape.is_buildable(to.x, to.z, 0.35):
			beast.offset = _graze_offset(herd) * 0.5
	elif moving:
		# Cohesion and alignment against the herd as a whole (its middle and its mean velocity,
		# one summary mate), separation against the few mates close enough to bump.
		var aim := Steering.flock_target(beast.mover, target, [_summary(herd, beast)], maxf(SPREAD * 3.0, beast.height * 4.0))
		var next := Steering.step(beast.mover, aim, _bumping(beast, mates), _close(herd.obstacles, beast.mover.position, pace), delta)
		var to := next.position as Vector3
		if not shape.is_buildable(to.x, to.z, 0.35):
			next["position"] = beast.mover.position
			next["velocity"] = Vector3.ZERO
			beast.offset = _graze_offset(herd) * 0.5
		beast.mover.merge(next, true)
		speed_now = Vector3(beast.mover.velocity).length()
		# Boxed in by its mates short of its spot: close enough, it settles where it is.
		if speed_now < pace * 0.15 and herd.mode in ["graze", "rest", "alert"] and away.length() < settle * 6.0:
			beast.settled = true
			if mother == null:
				beast.offset = _xz(beast.mover.position as Vector3) - _xz(herd.anchor)
	else:
		beast.mover["velocity"] = Vector3.ZERO
	var at := beast.mover.position as Vector3
	beast.node.position = Vector3(at.x, shape.height_at(at.x, at.z), at.z)
	beast.since = 0.0
	var heading := float(beast.mover.heading)
	if not moving and beast.doing == "alert":
		var look := herd.threat - beast.node.position
		heading = lerp_angle(beast.node.rotation.y, atan2(look.x, look.z), minf(delta * 4.0, 1.0))
		beast.mover["heading"] = heading
	beast.node.rotation.y = heading
	if beast.seen:
		_animate(beast, speed_now, walk, delta)


## Between full updates a moving animal keeps going the way it was, so far-off herds still
## move smoothly while their steering and animation run less often.
func _glide(beast: Beast, delta: float) -> void:
	var velocity := beast.mover.get("velocity", Vector3.ZERO) as Vector3
	if velocity.length_squared() < 0.0001:
		return
	beast.since += delta
	var at := (beast.mover.position as Vector3) + velocity * beast.since
	beast.node.position = Vector3(at.x, shape.height_at(at.x, at.z), at.z)


func _animate(beast: Beast, speed_now: float, walk: float, delta: float) -> void:
	var size := maxf(beast.height, 0.05)
	var down := 0.0
	if speed_now > walk * 1.6:
		AnimalArt.play(beast.node, "run", clampf(speed_now / (RUN_STRIDE * size), 0.5, 2.2))
	elif speed_now > 0.03:
		AnimalArt.play(beast.node, "walk", clampf(speed_now / (WALK_STRIDE * size), 0.4, 2.2))
	elif beast.doing in ["alert", "rest", "follow"] or beast.looking > 0.0 or beast.herd.hunter:
		AnimalArt.play(beast.node, "idle")
	else:
		AnimalArt.play(beast.node, "graze")
		down = 1.0
	AnimalArt.advance(beast.node, delta, down)


## A spot near `near` for an animal of this herd to graze.
func _graze_offset(herd: Herd) -> Vector3:
	var reach := SPREAD * sqrt(maxf(herd.members.size(), 1.0))
	var angle := _rng.randf() * TAU
	var radius := sqrt(_rng.randf()) * reach
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## Open land near a point: on the island, out of the water, clear of the camps, and (with a
## threat) at least keep_away from it. Falls back to the point itself.
func _spot(near: Vector3, radius: float, threat: Vector3, keep_away: float) -> Vector3:
	for attempt: int in 40:
		var angle := _rng.randf() * TAU
		var reach := sqrt(_rng.randf()) * radius * (1.0 + attempt * 0.05)
		var x := near.x + cos(angle) * reach
		var z := near.z + sin(angle) * reach
		if not shape.is_buildable(x, z, 0.9) or _near_camp(x, z) or (attempt < 30 and _wooded(x, z)):
			continue
		if threat != Vector3.INF and Vector2(x - threat.x, z - threat.z).length() < keep_away:
			continue
		return Vector3(x, 0.0, z)
	return Vector3(near.x, 0.0, near.z)


## Herds graze in the open: a spot with trees close around it is woods, and a rock is a rock.
func _wooded(x: float, z: float) -> bool:
	if sites == null:
		return false
	var close := 0
	for tree: Node3D in sites.trees:
		if Vector2(tree.position.x - x, tree.position.z - z).length_squared() < 1.2:
			close += 1
			if close >= 2:
				return true
	for rock: Node3D in sites.rocks:
		if Vector2(rock.position.x - x, rock.position.z - z).length_squared() < 1.0:
			return true
	return false


func _island_point() -> Vector3:
	var angle := _rng.randf() * TAU
	var reach := sqrt(_rng.randf()) * shape.radius * 0.8
	return Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)


func _near_camp(x: float, z: float) -> bool:
	for camp: Dictionary in _camps:
		var center := camp["center"] as Vector3
		if Vector2(x - center.x, z - center.z).length() < float(camp["radius"]) + CAMP_CLEARANCE:
			return true
	return false


## Where to put an animal: the point if it is open land, else the herd's middle.
func _on_land(at: Vector3, fallback: Vector3) -> Vector3:
	if shape.is_buildable(at.x, at.z, 0.35):
		return at
	return fallback


## Camps, the pond and the springs near a point, as Steering discs.
func _obstacles_near(at: Vector3) -> Array:
	var found: Array = []
	for camp: Dictionary in _camps:
		var center := camp["center"] as Vector3
		if Vector2(center.x - at.x, center.z - at.z).length() < float(camp["radius"]) + 6.0:
			found.append(Steering.disc_obstacle(center, float(camp["radius"]), "camp"))
	var pond := Vector3(shape.pond_center.x, 0.0, shape.pond_center.y)
	if pond.distance_to(Vector3(at.x, 0.0, at.z)) < shape.pond_radius + 6.0:
		found.append(Steering.disc_obstacle(pond, shape.pond_radius * 1.05, "pond"))
	if sites == null:
		return found
	# Rocks and tree trunks near the herd, nearest first, a handful at most.
	var near: Array = []
	for rock: Node3D in sites.rocks:
		var distance := Vector2(rock.position.x - at.x, rock.position.z - at.z).length()
		if distance < ROCK_REACH:
			near.append([distance, Steering.disc_obstacle(rock.position, ROCK_RADIUS * maxf(rock.scale.x, 0.6), "rock")])
	for tree: Node3D in sites.trees:
		var distance := Vector2(tree.position.x - at.x, tree.position.z - at.z).length()
		if distance < ROCK_REACH:
			near.append([distance, Steering.disc_obstacle(tree.position, TRUNK_RADIUS, "tree")])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for entry: Array in near.slice(0, MAX_PROPS):
		found.append(entry[1])
	return found


## Turns toward the spot and walks straight at it; returns the speed. Settles on arrival.
func _walk_straight(beast: Beast, away: Vector3, speed: float, delta: float, settle: float) -> float:
	var distance := away.length()
	var heading_to := atan2(away.x, away.z) if distance > 0.001 else float(beast.mover.heading)
	var turned := rotate_toward(float(beast.mover.heading), heading_to, 3.0 * delta)
	var forward := Vector3(sin(turned), 0.0, cos(turned))
	var step := minf(speed * delta, distance) * maxf(cos(angle_difference(turned, heading_to)), 0.0)
	beast.mover["position"] = (beast.mover.position as Vector3) + forward * step
	beast.mover["heading"] = turned
	beast.mover["velocity"] = forward * (step / maxf(delta, 0.001))
	if distance - step <= settle and beast.herd.mode in ["graze", "rest", "alert"]:
		beast.settled = true
		beast.mover["velocity"] = Vector3.ZERO
	return step / maxf(delta, 0.001)


## The herd seen as one mate: its middle and its mean velocity, leaving this animal out.
func _summary(herd: Herd, beast: Beast) -> Dictionary:
	var count := herd.members.size()
	if count <= 1:
		return {"position": beast.mover.position, "velocity": Vector3.ZERO, "id": beast.id}
	var middle := Vector3.ZERO
	var velocity := Vector3.ZERO
	for other: Beast in herd.members:
		if other == beast:
			continue
		middle += other.mover.position as Vector3
		velocity += other.mover.velocity as Vector3
	return {"position": middle / float(count - 1), "velocity": velocity / float(count - 1), "id": -1}


## The mates near enough to need room made from them.
static func _bumping(beast: Beast, mates: Array) -> Array:
	var near: Array = []
	var at := beast.mover.position as Vector3
	var reach := float(beast.mover.comfort) * 1.5
	for mate: Dictionary in mates:
		var other := mate.position as Vector3
		if absf(other.x - at.x) < reach and absf(other.z - at.z) < reach:
			near.append(mate)
	return near


## The obstacles a moving animal could touch before its next update.
static func _close(obstacles: Array, at: Vector3, pace: float) -> Array:
	var found: Array = []
	var reach := 0.6 + pace * 0.6
	for obstacle: Dictionary in obstacles:
		var center := obstacle["center"] as Vector3
		if Vector2(center.x - at.x, center.z - at.z).length() < float(obstacle["radius"]) + reach:
			found.append(obstacle)
	return found


static func _xz(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)
