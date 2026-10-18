class_name Settlement
extends Node3D
## One tribe on the island, drawn from the simulation: the fire at its heart, every building on
## its slot (rising out of a building site while builders work on it), and every person going
## about their day. Workers walk out to the trees, rocks, bushes, shores and fields with the tool
## of their trade, work there, and come home carrying what they gathered; builders hammer at the
## current project; children play around the fire and babies stay with their mothers; the sick
## lie by their door; mourners visit the graves; elders sit by the fire. Meetings the sim reports
## (a chat, a quarrel, a courtship) are acted out, newborns appear beside their mother, and the
## dead fall and are buried on the hill outside the village.
## In the later ages the miners, smiths, scholars, merchants, officials and factory hands go to
## their own buildings; guards in helmets patrol the street between the inner rings or stand at
## the watchtower, barracks, prison or great house; nobles dress finer and the bonded plainer;
## and anyone in custody is held in the prison yard (or out of sight, where there is no prison).
## Visual only: randomness here never touches the simulation.

## Ring 3 (mines, factories, prisons, towers) stays inside half of IslandShape.CAMP_SPACING
## where it can, and its slots step aside from neighboring camps and the graveyard.
const RING_RADII: Array[float] = [1.3, 2.2, 3.05, 3.8]
const WALL_RADIUS := 2.68 ## the palisade or stone wall, between the middle and outer rings
const WALK_SPEED := 0.42 ## world units per second
const RUN_SPEED := 0.8
## Same accel and turn rate as the building-footprint steering check.
const STEER_ACCEL := 1.4
const STEER_TURN := 3.2
## Spokes join the rings. The two gates face +Z (the wall mesh) and the far side.
const SPOKE_ANGLES: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
const GATE_ANGLES: Array[float] = [0.0, PI]
const GATE_HALF := 0.34 ## rad; drops the two segments that meet at a gate
const WALL_SEGMENTS := 24
const MAX_GRAVES := 40
const MEET_SECONDS := 3.5
const MAX_MEETINGS := 8 ## acted out at once
const EMOTES := {"chat": ["…", Color(1.0, 0.97, 0.9)], "love": ["♥", Color(1.0, 0.45, 0.55)], "flirt": ["♥", Color(1.0, 0.6, 0.7)],
	"quarrel": ["!", Color(1.0, 0.55, 0.3)], "fight": ["✊", Color(1.0, 0.35, 0.25)]}
const TOOLS := {"forager": "basket", "hunter": "spear", "fisher": "rod", "farmer": "hoe", "woodcutter": "axe",
	"quarrier": "pickaxe", "builder": "hammer", "healer": "bowl", "toolmaker": "hammer",
	"miner": "pickaxe", "smith": "hammer", "scholar": "book", "merchant": "purse", "guard": "pike",
	"official": "scroll", "factory_worker": "wrench"}
const CARRIES := {"forager": "food", "hunter": "food", "fisher": "fish", "farmer": "food", "woodcutter": "wood", "quarrier": "stone",
	"miner": "stone", "factory_worker": "goods"}
const SWING_JOBS: Array[String] = ["woodcutter", "quarrier", "builder", "toolmaker", "miner", "smith", "factory_worker"]
## Where guards stand watch when they aren't walking the rounds.
const GUARD_POSTS: Array[String] = ["watchtower", "barracks", "prison", "great_house"]
const BRONZE := Color(0.80, 0.58, 0.36)
const STEEL := Color(0.66, 0.66, 0.72)


## One person's figure and what it is doing.
class Walker:
	var id: int
	var node: Node3D
	var key := ""
	var target := Vector3.ZERO
	var phase := ""
	var timer := 0.0
	var walking := 0.0
	var speed := WALK_SPEED
	var activity := ""
	var job := ""
	var home := -1
	var mother := -1
	var partner := -1 ## who they are meeting, or -1
	var meet_kind := ""
	var emote: Label3D
	var lying := 0.0
	var work_phase := 0.0
	var seated := false ## ground-sit clip is on
	var dying := 0.0 ## counts up once they have died
	var status := "" ## "", "noble" or "bonded"
	var detained := false
	var patrol := false ## a guard walking the rounds
	var patrol_angle := 0.0
	var mover: Dictionary = {} ## last Steering.mover: position, velocity, heading
	var age := 30
	var health := 100.0
	var mood := 55.0
	var sick := false ## days of sickness left, apart from activity == "sick"
	var traits := PackedStringArray()
	var height := 0.5
	var build := 0.5
	var gait_key := ""
	var gait_speed := WALK_SPEED
	var comfort := 0.58
	var drift_speed := 0.0
	var drift_ready := false
	var lane_route: Array[Vector3] = []
	var lane_goal := Vector3.INF
	var stuck := 0.0 ## seconds barely moving while a footprint still holds the target


var tribe_name: String
var shape: IslandShape
var sites: WorkSites
var tint: Color

var _rng := RandomNumberGenerator.new()
var _fire: Node3D
var _buildings: Dictionary = {} ## building id -> Node3D
var _building_keys: Dictionary = {} ## building id -> what it was built as, to rebuild when it changes
var _building_spots: Dictionary = {} ## building id -> local position
var _building_types: Dictionary = {} ## building id -> type
var _slot_spots: Dictionary = {} ## slot -> local position on land
var _walkers: Dictionary = {} ## person id -> Walker
var _graves: Array[Node3D] = []
var _month := -1
var _age := 0
var _water := 0
var _project := -1
var _sick_homes: Array[int] = []
var _selection_ring: MeshInstance3D
var _focus_ring: MeshInstance3D
var _name_tag: Label3D
var _focused := -1
var _style: Dictionary = {} ## the tribe's look (StyleKind's spec): stored in the world, or written offline
var _style_stamp := "" ## what _style was read for; read again when it changes
var _fashion_key := "" ## a short key of the fashion, so figures redress when it changes
var _emblems_due := 0 ## msec when the banner, posters and monuments are next checked
var _banner: Node3D
var _banner_key := ""
var _posters: Array[Node3D] = []
var _posters_key := ""
var _obstacles: Array = [] ## building discs, the fire, and wall capsules
var _obstacle_stamp := ""
var _obstacles_ready := false
var _lanes: Lanes


func setup(name_of_tribe: String, island: IslandShape, work_sites: WorkSites) -> void:
	tribe_name = name_of_tribe
	shape = island
	sites = work_sites
	_rng.seed = hash(name_of_tribe)
	var hue := fposmod(float(hash(name_of_tribe) % 1000) / 1000.0, 1.0)
	tint = Color.from_hsv(hue, 0.55, 0.85)
	_fire = Props.campfire()
	add_child(_fire)
	_pop_in(_fire)
	for i: int in 3:
		var clutter := Props.camp_clutter(_rng)
		var angle := _rng.randf() * TAU
		clutter.position = Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.42, 0.6)
		clutter.position.y = _ground(clutter.position)
		clutter.rotation.y = _rng.randf() * TAU
		add_child(clutter)
	# The founders clear the land they settle.
	sites.clear(position, RING_RADII[2] + 0.5, false)


# --- Picking and focus --------------------------------------------------------------

func figure(id: int) -> Node3D:
	var walker: Walker = _walkers.get(id)
	return walker.node if walker and walker.dying == 0.0 else null


func person_ids() -> Array:
	return _walkers.keys().filter(func(id: int) -> bool: return (_walkers[id] as Walker).dying == 0.0)


## World position of a person's figure, or null.
func person_position(id: int) -> Variant:
	var walker: Walker = _walkers.get(id)
	return walker.node.global_position if walker else null


func set_selected(selected: bool) -> void:
	if selected and _selection_ring == null:
		var torus := TorusMesh.new()
		torus.inner_radius = RING_RADII[3] + 0.45
		torus.outer_radius = RING_RADII[3] + 0.53
		torus.rings = 64
		_selection_ring = MeshInstance3D.new()
		_selection_ring.mesh = torus
		_selection_ring.material_override = ToonMaterials.emissive(Color(1.0, 0.92, 0.6), Color(1.0, 0.8, 0.4))
		_selection_ring.position.y = 0.1
		add_child(_selection_ring)
	if _selection_ring:
		_selection_ring.visible = selected


## Rings the person being inspected and shows their name above them; -1 clears it.
func set_focus(id: int, label: String) -> void:
	_focused = id
	var walker: Walker = _walkers.get(id)
	var target: Node3D = walker.node if walker else null
	if _focus_ring == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.2
		torus.outer_radius = 0.26
		torus.rings = 24
		_focus_ring = MeshInstance3D.new()
		_focus_ring.mesh = torus
		_focus_ring.material_override = ToonMaterials.emissive(Color(1.0, 0.95, 0.7), Color(1.0, 0.85, 0.45))
		_name_tag = Label3D.new()
		_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_name_tag.font = UiStyle.font("strong")
		_name_tag.font_size = 40
		_name_tag.outline_size = 10
		_name_tag.outline_modulate = ToonMaterials.INK
		_name_tag.pixel_size = 0.005
		_name_tag.no_depth_test = true
	for node: Node3D in [_focus_ring, _name_tag]:
		if node.get_parent() != target:
			if node.get_parent():
				node.get_parent().remove_child(node)
			if target:
				target.add_child(node)
	if target:
		_focus_ring.position.y = 0.04
		_name_tag.text = label
		_name_tag.position.y = VillagerArt.HEIGHT * float(target.get_meta("growth", 1.0)) + 0.28


# --- Keeping up with the simulation -------------------------------------------------

## people: person id -> {"female", "age", "chief", "genome", "activity", "job", "home", "mother", "newborn"}.
## arrivals: person id -> world position they were last seen at (moving in from another tribe).
## Rank and custody are read from the state directly.
func sync(state: WorldState, people: Dictionary, arrivals: Dictionary) -> void:
	var t := state.tribe_index(tribe_name)
	_water = state.tribe_water[t]
	_project = state.tribe_project[t]
	_age = state.age_of(t)
	_sync_style(state)
	_sync_buildings(state)
	_sync_emblems(state)
	_sick_homes.clear()
	for id: int in people:
		var info: Dictionary = people[id]
		if info["activity"] == "sick" and int(info["home"]) != -1:
			_sick_homes.append(int(info["home"]))
	for id: int in _walkers.keys():
		var walker := _walkers[id] as Walker
		if not people.has(id) and walker.dying == 0.0:
			_leave(walker)
	for id: int in people:
		var p := state.index_of(id)
		var status := state.person_status[p] if p != -1 else ""
		var detained := p != -1 and state.person_detained[p] > 0
		_sync_person(id, people[id], arrivals, status, detained)
		_read_body(_walkers[id] as Walker, state, p, people[id])


func _sync_buildings(state: WorldState) -> void:
	var month := state.month()
	var seen := {}
	for b: int in state.buildings_of(tribe_name):
		var id := state.building_ids[b]
		var type := state.building_types[b]
		if type == "fire":
			continue
		seen[id] = true
		var built := state.is_built(b)
		# Rebuilt in place (a hut becoming a row house) or finished, the model swaps.
		var key := "%s|%s|%s|%s" % [type, BuildingArt.variant(type, _age), StyledBuildings.key(type, _style), built]
		if _building_keys.get(id, "") != key:
			_build(id, type, state.building_slots[b], built)
			_building_keys[id] = key
		if not built:
			var progress := float(state.building_progress[b]) / maxf(float(Buildings.TYPES[type]["work"]), 1.0)
			_show_progress(id, type, progress)
	for id: int in _buildings.keys():
		if not seen.has(id):
			_vanish(_buildings[id] as Node3D)
			_buildings.erase(id)
			_building_keys.erase(id)
			_building_spots.erase(id)
			_building_types.erase(id)
	if month != _month:
		_month = month
		for id: int in _buildings:
			if _building_types[id] == "field":
				var model := (_buildings[id] as Node3D).get_node_or_null("Model") as Node3D
				if model:
					BuildingArt.set_season(model, month)


## Reads the tribe's style (architecture and fashion) when the stored spec changes, or, while the
## world has none yet, when what it would be written for changes (see AssetDirector.spec_or_offline).
## Buildings and figures whose look changed then rebuild, popping in anew.
func _sync_style(state: WorldState) -> void:
	var entry: Dictionary = state.assets.get(AssetBook.key("style", tribe_name), {})
	var stamp := "%s@%s" % [entry.get("signature", ""), entry.get("tick", 0)]
	if entry.is_empty():
		var kind := AssetKinds.find("style")
		stamp = "offline|" + (kind.signature(state, tribe_name) if kind else "")
	if stamp == _style_stamp:
		return
	_style_stamp = stamp
	_style = AssetDirector.spec_or_offline(state, "style", tribe_name)
	_fashion_key = str(hash(_style.get("fashion", {})))


## Whose clothes a person wears: the bonded and nobles by rank, guards by their job.
static func _dress_class(status: String, job: String) -> String:
	if status == "bonded":
		return "bonded"
	if job == "guard":
		return "guard"
	return "noble" if status == "noble" else "commoner"


## A building's node: a site with the building rising out of it, or the finished building.
func _build(id: int, type: String, slot: int, built: bool) -> void:
	if _buildings.has(id):
		(_buildings[id] as Node3D).queue_free()
	var holder := Node3D.new()
	var wall := type in Buildings.WALLS
	var spot := _slot_spot(slot) if not wall else Vector3.ZERO
	holder.position = spot
	holder.position.y = _ground(spot)
	if not wall and spot.length() > 0.01:
		var to_fire := -spot
		holder.rotation.y = atan2(to_fire.x, to_fire.z) if type != "field" else atan2(spot.x, spot.z) + PI / 2.0
	var model := BuildingArt.wall(type, WALL_RADIUS, tint) if wall else BuildingArt.make(type, tint, _age, _style)
	model.name = "Model"
	if wall:
		# Where a neighbor is close, the wall stops at the line between the two villages.
		for piece: Node in model.get_children():
			if not _own_side((piece as Node3D).position, 0.2):
				model.remove_child(piece)
				piece.free()
	holder.add_child(model)
	if type == "field":
		BuildingArt.set_season(model, maxi(_month, 0))
	BuildingArt.set_active(model, built)
	if not built:
		var site := BuildingArt.building_site(type) if not wall else Node3D.new()
		site.name = "Site"
		holder.add_child(site)
		model.scale = Vector3(1.0, 0.05, 1.0)
	add_child(holder)
	if built:
		_pop_in(model)
	else:
		_pop_in(holder)
	_buildings[id] = holder
	_building_spots[id] = holder.position
	_building_types[id] = type
	if BuildingArt.SIZES.has(type):
		var size: Vector3 = BuildingArt.SIZES[type]
		sites.clear(position + spot, maxf(size.x, size.y) + 0.3)
	elif type in ["longhouse", "storehouse", "field", "shrine"]:
		sites.clear(position + spot, 0.75)
	elif not wall:
		sites.clear(position + spot, 0.5)


## The building grows up out of its site as the builders work.
func _show_progress(id: int, type: String, progress: float) -> void:
	var model := (_buildings[id] as Node3D).get_node_or_null("Model") as Node3D
	if model == null:
		return
	if type in Buildings.WALLS:
		var shown := roundi(progress * model.get_child_count())
		for k: int in model.get_child_count():
			(model.get_child(k) as Node3D).visible = k < shown
		return
	model.scale.y = move_toward(model.scale.y, lerpf(0.08, 0.9, progress), 0.02)


## True when the current walk should be dropped. Job and home are not arguments, so those changes
## finish the trip, and so does a switch among playing, mourning, working, teaching and idle.
## Becoming sick, an infant or resting (and getting back up), custody flipping, or dying replans now.
static func interrupts(was_activity: String, activity: String, was_detained: bool, detained: bool, dying: float) -> bool:
	if dying > 0.0 or was_detained != detained:
		return true
	if was_activity == activity:
		return false
	var finishes := ["playing", "mourning", "working", "teaching", "idle"]
	return was_activity not in finishes or activity not in finishes


func _sync_person(id: int, info: Dictionary, arrivals: Dictionary, status: String, detained: bool) -> void:
	var age := int(info["age"])
	var dress_class := _dress_class(status, String(info["job"]))
	var key := "%s|%s|%s|%s" % [VillagerArt.looks_key(age, info["chief"]), status, dress_class, _fashion_key]
	var walker: Walker = _walkers.get(id)
	if walker == null:
		walker = Walker.new()
		walker.id = id
		_walkers[id] = walker
	if walker.key != key:
		var looks := VillagerArt.wear(VillagerArt.appearance_of(info["genome"], id, info["female"], age, info["chief"], tint), _style.get("fashion", {}), dress_class, tint)
		walker.status = status
		var old := walker.node
		walker.node = VillagerArt.make(looks)
		walker.key = key
		VillagerArt.offset_time(walker.node, _rng.randf() * 2.0)
		add_child(walker.node)
		if old:
			walker.node.transform = old.transform
			for keep: Node3D in [_focus_ring, _name_tag]:
				if keep and keep.get_parent() == old:
					old.remove_child(keep)
					walker.node.add_child(keep)
			old.queue_free()
		else:
			walker.node.position = _arrival_spot(walker, info, arrivals)
			# Someone already in custody when first seen starts out in the prison yard.
			var yard := _yard_spot() if detained else Vector3.INF
			if yard != Vector3.INF:
				walker.node.position = yard
			_pop_in(walker.node)
		walker.phase = ""
		walker.seated = false
		VillagerArt.set_tool(walker.node, "")
		walker.job = ""
	var was_activity := walker.activity
	var was_detained := walker.detained
	if walker.detained != detained:
		walker.detained = detained
		walker.job = ""
		walker.node.visible = true
	if walker.activity != info["activity"] or walker.job != info["job"] or walker.home != int(info["home"]):
		walker.activity = info["activity"]
		walker.job = info["job"]
		walker.home = int(info["home"])
		walker.mother = int(info["mother"])
		var working := walker.activity == "working" and not walker.detained
		VillagerArt.set_tool(walker.node, String(TOOLS.get(walker.job, "")) if working else "")
		if not working:
			VillagerArt.set_carry(walker.node, "")
		# Guards wear their helmets and officials their caps on duty or off; not in a cell.
		var gear := "" if walker.detained else String({"guard": "helmet", "official": "cap"}.get(walker.job, ""))
		VillagerArt.set_headgear(walker.node, gear, BRONZE if _age < 2 else STEEL, tint)
	# A meeting keeps its phase. Solo walks drop only when the person must react immediately.
	if walker.partner == -1 and interrupts(was_activity, walker.activity, was_detained, walker.detained, walker.dying):
		walker.phase = ""


## Where a new figure appears: beside the mother for a newborn, where they were last seen for
## someone moving in from another tribe, else by the fire.
func _arrival_spot(walker: Walker, info: Dictionary, arrivals: Dictionary) -> Vector3:
	if arrivals.has(walker.id):
		var from: Vector3 = arrivals[walker.id]
		return Vector3(from.x - position.x, from.y - position.y, from.z - position.z)
	var mother: Walker = _walkers.get(int(info["mother"]))
	if info.get("newborn", false) and mother and mother.node:
		return mother.node.position + Vector3(0.12, 0.0, 0.08)
	return _near_fire(0.6)


func _leave(walker: Walker) -> void:
	_walkers.erase(walker.id)
	_vanish(walker.node)


## The person has died: they fall, fade, and a grave is dug on the hill.
func bury(id: int, chief: bool) -> void:
	var walker: Walker = _walkers.get(id)
	if walker:
		walker.dying = 0.001
		walker.partner = -1
		VillagerArt.set_tool(walker.node, "")
		VillagerArt.set_carry(walker.node, "")
		VillagerArt.set_walking(walker.node, 0.0)
	var grave := BuildingArt.grave(_rng, chief)
	grave.position = _grave_spot(_graves.size())
	grave.position.y = _ground(grave.position)
	grave.rotation.y = atan2(grave.position.x, grave.position.z)
	add_child(grave)
	_pop_in(grave)
	_graves.append(grave)
	if _graves.size() > MAX_GRAVES:
		_vanish(_graves.pop_front())


## Acts out a meeting between two people of this tribe.
func meet(a: int, b: int, kind: String) -> void:
	var first: Walker = _walkers.get(a)
	var second: Walker = _walkers.get(b)
	if first == null or second == null or first.dying > 0.0 or second.dying > 0.0:
		return
	if first.partner != -1 or second.partner != -1 or first.lying > 0.1 or second.lying > 0.1:
		return
	if first.activity == "infant" or second.activity == "infant" or first.detained or second.detained:
		return
	var busy := 0
	for walker: Walker in _walkers.values():
		if walker.partner != -1:
			busy += 1
	if busy >= MAX_MEETINGS * 2:
		return
	var middle := (first.node.position + second.node.position) / 2.0
	if middle.length() > RING_RADII[2] + 1.0:
		middle = middle.normalized() * (RING_RADII[1])
	for pair: Array in [[first, second, 0.14], [second, first, -0.14]]:
		var walker: Walker = pair[0]
		var other: Walker = pair[1]
		walker.partner = other.id
		walker.meet_kind = kind
		walker.phase = "to_meet"
		walker.timer = 6.0
		var side := (other.node.position - walker.node.position).normalized()
		walker.target = middle - side * 0.14
		_apply_speed(walker)


# --- Behavior -----------------------------------------------------------------------

func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	if _fire:
		var flame := _fire.get_node("Flame") as Node3D
		var flicker := 0.85 + 0.15 * sin(time * 13.0 + _buildings.size()) + 0.08 * sin(time * 23.0)
		flame.scale = Vector3(1.0, flicker, 1.0)
		(_fire.get_node("Light") as OmniLight3D).light_energy = 1.4 * flicker
	if _selection_ring and _selection_ring.visible:
		_selection_ring.scale = Vector3.ONE * (1.0 + 0.01 * sin(time * 4.0))
	if _focus_ring and _focus_ring.get_parent():
		_focus_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(time * 5.0))
	for walker: Walker in _walkers.values():
		if walker.dying == 0.0:
			_apply_speed(walker)
	var neighbors := _camp_neighbors()
	var obstacles := _camp_obstacles()
	for walker: Walker in _walkers.values():
		if walker.dying > 0.0:
			_die_step(walker, delta)
		else:
			_step(walker, delta, time, neighbors, obstacles)


func _die_step(walker: Walker, delta: float) -> void:
	walker.dying += delta
	if walker.seated:
		VillagerArt.set_work(walker.node, 0.0)
		walker.seated = false
	VillagerArt.set_lying(walker.node, clampf(walker.dying / 0.8, 0.0, 1.0))
	if walker.dying > 1.6 and _walkers.get(walker.id) == walker:
		for keep: Node3D in [_focus_ring, _name_tag]:
			if keep and keep.get_parent() == walker.node:
				walker.node.remove_child(keep)
		_walkers.erase(walker.id)
		_vanish(walker.node)


func _step(walker: Walker, delta: float, time: float, neighbors: Array, obstacles: Array) -> void:
	var node := walker.node
	# _plan fills an empty phase, so remember it for the sit check below.
	var unplanned := walker.phase.is_empty()
	if unplanned:
		_plan(walker)
	_apply_speed(walker)
	# Lie down when sick at home, stand up otherwise.
	var lie := 1.0 if walker.phase == "lie" else 0.0
	if not is_equal_approx(walker.lying, lie):
		walker.lying = move_toward(walker.lying, lie, delta * 1.5)
		VillagerArt.set_lying(node, walker.lying)
	# Babies stay with their mother.
	if walker.phase == "follow":
		var mother: Walker = _walkers.get(walker.mother)
		if mother and mother.dying == 0.0:
			walker.target = mother.node.position + Vector3(0.13, 0.0, 0.09).rotated(Vector3.UP, mother.node.rotation.y)
		elif walker.timer <= 0.0:
			walker.target = _home_spot(walker.home)
			walker.timer = 3.0
	var to_target := walker.target - node.position
	to_target.y = 0.0
	var distance := to_target.length()
	var settled := walker.phase in ["work", "rest", "lie", "meet", "drop"]
	var turn_in_place := false
	if not settled and distance > 0.04:
		var stepped := _steer(walker, _aim(walker), neighbors, obstacles, delta)
		turn_in_place = bool(stepped.turn_in_place)
		to_target = walker.target - node.position
		to_target.y = 0.0
		distance = to_target.length()
	elif not walker.mover.is_empty():
		walker.mover["velocity"] = Vector3.ZERO
		walker.mover["position"] = node.position
		walker.mover["heading"] = node.rotation.y
	var speed_now := 0.0 if walker.mover.is_empty() else Vector3(walker.mover.velocity).length()
	# A building disc can hold the target inside it. Standing there still counts as arriving.
	if turn_in_place or settled or speed_now >= 0.025 or distance >= 1.05 or distance <= 0.04:
		walker.stuck = 0.0
	else:
		walker.stuck += delta
	var moving := not settled and distance > 0.04 and walker.stuck < 0.4
	# turn_in_place already stops the stride. Don't lerp a second turn on top.
	var stride := moving and not turn_in_place
	walker.walking = move_toward(walker.walking, 1.0 if stride else 0.0, delta * 3.0)
	VillagerArt.set_walking(node, walker.walking)
	# Working motion.
	if walker.phase == "work":
		walker.work_phase += delta
		if walker.job in SWING_JOBS:
			VillagerArt.set_work(node, 0.15, maxf(sin(walker.work_phase * 5.0), 0.0))
		elif walker.job in ["forager", "farmer", "healer"]:
			VillagerArt.set_work(node, 0.9 + 0.25 * sin(walker.work_phase * 2.0))
		elif walker.job == "guard":
			VillagerArt.set_work(node, 0.0)
		elif walker.job in ["scholar", "official"]:
			VillagerArt.set_work(node, 0.3 + 0.05 * sin(walker.work_phase * 0.8))
		else:
			VillagerArt.set_work(node, 0.2 + 0.1 * sin(walker.work_phase * 1.5))
	elif walker.work_phase != 0.0:
		walker.work_phase = 0.0
		VillagerArt.set_work(node, 0.0)
	# Rest sits. So does a teacher or mourner with no phase who has not started walking.
	# Lie stays on set_lying. Walk, work, meet, and lie leave the sit clip.
	var sitting := walker.phase == "rest" or (unplanned and walker.activity in ["teaching", "mourning"] and not moving)
	if sitting:
		VillagerArt.set_work(node, 0.0, 0.0, "sit")
		walker.seated = true
	elif walker.seated and (moving or walker.phase == "work" or walker.phase == "meet" or walker.phase == "lie"):
		# Work already called set_work with the default action "", which clears sit.
		if walker.phase != "work":
			VillagerArt.set_work(node, 0.0)
		walker.seated = false
	if walker.phase == "meet":
		var other: Walker = _walkers.get(walker.partner)
		if other:
			var look := other.node.position - node.position
			node.rotation.y = lerp_angle(node.rotation.y, atan2(look.x, look.z), minf(delta * 6.0, 1.0))
		if walker.emote:
			walker.emote.position.y = VillagerArt.HEIGHT * float(node.get_meta("growth", 1.0)) + 0.12 + 0.04 * sin(time * 4.0)
	walker.timer -= delta
	var staying := walker.phase in ["work", "rest", "lie", "meet", "drop", "follow"]
	if walker.timer <= 0.0 or (not staying and not moving):
		_advance(walker)
	if not walker.mover.is_empty():
		walker.mover["position"] = node.position
		walker.mover["heading"] = node.rotation.y


## What to do when someone arrives or their time is up.
func _advance(walker: Walker) -> void:
	match walker.phase:
		"to_work":
			walker.phase = "work"
			walker.timer = _rng.randf_range(0.6, 1.6) if walker.patrol else _rng.randf_range(5.0, 11.0)
			if not walker.patrol:
				_face(walker, walker.target + (walker.target - _home_spot(walker.home)).normalized() * 0.3)
		"work":
			var carry := String(CARRIES.get(walker.job, ""))
			if walker.patrol:
				walker.phase = ""
			elif carry:
				VillagerArt.set_carry(walker.node, carry)
				walker.phase = "to_drop"
				walker.target = _drop_spot(walker.job)
				walker.timer = 30.0
			else:
				walker.phase = "rest"
				walker.timer = _rng.randf_range(1.5, 3.0)
		"to_drop":
			walker.phase = "drop"
			walker.timer = 1.2
		"drop":
			VillagerArt.set_carry(walker.node, "")
			if _rng.randf() < 0.35:
				walker.phase = "to_rest"
				walker.target = _near_fire(0.75)
				walker.timer = 20.0
			else:
				walker.phase = ""
		"to_rest":
			walker.phase = "rest"
			walker.timer = _rng.randf_range(2.0, 5.0)
		"to_meet":
			walker.phase = "meet"
			walker.timer = MEET_SECONDS
			_show_emote(walker)
		"meet":
			_end_meeting(walker)
		"to_home":
			walker.phase = "lie" if walker.activity == "sick" else "rest"
			walker.timer = _rng.randf_range(6.0, 12.0)
		"lie":
			walker.timer = _rng.randf_range(6.0, 12.0)
		"follow":
			walker.timer = 0.5
		"wander":
			walker.phase = "rest"
			walker.timer = _rng.randf_range(0.3, 1.2) if walker.activity == "playing" else _rng.randf_range(1.5, 5.0)
		_:
			walker.phase = ""


func _plan(walker: Walker) -> void:
	walker.patrol = false
	if walker.detained:
		_hold(walker)
		return
	match walker.activity:
		"infant":
			walker.phase = "follow"
			walker.timer = 0.5
		"playing":
			# Children run about the whole village, and sometimes tag along with a parent.
			walker.phase = "wander"
			var parent: Walker = _walkers.get(walker.mother)
			if parent and parent.dying == 0.0 and _rng.randf() < 0.25:
				walker.target = parent.node.position + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
			else:
				walker.target = _near_fire(_rng.randf_range(0.6, RING_RADII[1] + 0.4))
			walker.timer = _rng.randf_range(1.0, 3.0)
		"sick", "resting":
			walker.phase = "to_home"
			walker.target = _home_spot(walker.home)
			walker.timer = 30.0
		"mourning":
			walker.phase = "to_rest"
			walker.target = _grave_spot(maxi(_graves.size() - 1, 0)) + Vector3(0.25, 0.0, 0.2)
			walker.timer = 30.0
		"teaching":
			walker.phase = "to_rest"
			var angle := float(walker.id % 12) / 12.0 * TAU
			walker.target = Vector3(cos(angle), 0.0, sin(angle)) * 0.7
			walker.timer = 30.0
		"working":
			walker.phase = "to_work"
			walker.target = _work_spot(walker)
			walker.timer = 40.0
		_:
			walker.phase = "wander"
			walker.target = _near_fire(_rng.randf_range(0.6, 1.8)) if _rng.randf() < 0.6 else _home_spot(walker.home)
			walker.timer = _rng.randf_range(4.0, 8.0)


## Where someone's job takes them, in this settlement's space.
func _work_spot(walker: Walker) -> Vector3:
	var from := walker.node.global_position
	var world: Vector3
	match walker.job:
		"forager":
			world = sites.bush_near(position, _rng)
		"hunter":
			world = sites.hunting_ground(position, _rng)
		"fisher":
			world = sites.shore(_water, position, _rng)
		"woodcutter":
			world = sites.nearest_tree(from)
			world += (from - world).normalized() * 0.3
		"quarrier":
			world = sites.nearest_rock(from)
			world += (from - world).normalized() * 0.45
		"farmer":
			var field := _a_building("field")
			if field != -1:
				return _building_spots[field] + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.3, 0.3))
			world = sites.bush_near(position, _rng)
		"builder":
			if _buildings.has(_project):
				return _building_spots[_project] + Vector3(_rng.randf_range(-0.45, 0.45), 0.0, _rng.randf_range(-0.45, 0.45))
			return _near_fire(_rng.randf_range(1.0, 2.0))
		"healer":
			if not _sick_homes.is_empty():
				return _home_spot(_sick_homes[_rng.randi_range(0, _sick_homes.size() - 1)])
			return _beside("healer_hut", 0.4)
		"toolmaker":
			return _beside("workshop", 0.25)
		"potter", "weaver":
			return _beside("storehouse", 0.45)
		"shaman":
			return _beside("shrine", 0.3)
		"miner":
			return _beside("mine", 0.55)
		"smith":
			return _beside("smithy", 0.32)
		"scholar":
			return _beside("school", 0.45)
		"merchant":
			return _beside("market", 0.12)
		"factory_worker":
			return _beside("factory", 0.55)
		"official":
			# At the ruler's seat, or out on the rounds of the homes.
			var homes := _buildings_where(func(type: String) -> bool: return Buildings.is_home(type))
			if _rng.randf() < 0.4 and not homes.is_empty():
				return _home_spot(homes[_rng.randi_range(0, homes.size() - 1)])
			return _beside("great_house", 0.5)
		"guard":
			return _guard_spot(walker)
		_:
			return _near_fire(1.0)
	return Vector3(world.x - position.x, 0.0, world.z - position.z)


## A guard stands watch at a post (a watchtower, the barracks, the prison or the great house), or
## walks the rounds along the street between the inner and middle rings, a stretch at a time.
func _guard_spot(walker: Walker) -> Vector3:
	var posts := _buildings_where(func(type: String) -> bool: return type in GUARD_POSTS)
	if not posts.is_empty() and _rng.randf() < 0.35:
		var spot: Vector3 = _building_spots[posts[_rng.randi_range(0, posts.size() - 1)]]
		return spot + (-spot).normalized() * 0.45 + Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12))
	if not walker.patrol:
		walker.patrol_angle = atan2(walker.node.position.z, walker.node.position.x)
	walker.patrol = true
	walker.patrol_angle += 0.55 * (1.0 if walker.id % 2 == 0 else -1.0)
	var street := (RING_RADII[0] + RING_RADII[1]) / 2.0
	return Vector3(cos(walker.patrol_angle), 0.0, sin(walker.patrol_angle)) * street


## Someone in custody paces the prison yard; where there is no prison, they are out of sight.
func _hold(walker: Walker) -> void:
	VillagerArt.set_tool(walker.node, "")
	VillagerArt.set_carry(walker.node, "")
	walker.phase = "to_rest"
	walker.timer = 30.0
	var yard := _yard_spot()
	if yard == Vector3.INF:
		walker.node.visible = false
		walker.phase = "rest"
		walker.timer = 8.0
		return
	walker.node.visible = true
	walker.target = yard


## A spot in a prison's yard, or Vector3.INF if the village has no prison.
func _yard_spot() -> Vector3:
	var prison := _a_building("prison")
	if prison == -1:
		return Vector3.INF
	var yard := BuildingArt.PRISON_YARD + Vector3(_rng.randf_range(-0.28, 0.28), 0.0, _rng.randf_range(-0.1, 0.12))
	var spot := (_buildings[prison] as Node3D).transform * yard
	return Vector3(spot.x, _ground(spot), spot.z)


## Finished buildings whose type passes a test.
func _buildings_where(test: Callable) -> Array[int]:
	var found: Array[int] = []
	for id: int in _building_types:
		if test.call(_building_types[id]) and _building_keys.get(id, "").ends_with("true"):
			found.append(id)
	return found


func _a_building(type: String) -> int:
	var found: Array[int] = []
	for id: int in _building_types:
		if _building_types[id] == type and _building_keys.get(id, "").ends_with("true"):
			found.append(id)
	return found[_rng.randi_range(0, found.size() - 1)] if not found.is_empty() else -1


func _beside(type: String, distance: float) -> Vector3:
	var id := _a_building(type)
	if id == -1:
		return _near_fire(_rng.randf_range(0.6, 1.2))
	var spot: Vector3 = _building_spots[id]
	return spot + (-spot).normalized() * distance + Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.15, 0.15))


## Where a worker drops what they carry: ore goes to the smithy and goods to the market when
## there is one, everything else to the storehouse.
func _drop_spot(job: String) -> Vector3:
	var to := {"miner": "smithy", "factory_worker": "market"}.get(job, "storehouse") as String
	var store := _a_building(to)
	if store == -1:
		store = _a_building("storehouse")
	if store != -1:
		var spot: Vector3 = _building_spots[store]
		return spot + (-spot).normalized() * 0.4
	return _near_fire(0.55)


func _home_spot(home: int) -> Vector3:
	if _building_spots.has(home):
		var spot: Vector3 = _building_spots[home]
		return spot + (-spot).normalized() * 0.42
	return _near_fire(0.9)


func _near_fire(radius: float) -> Vector3:
	var angle := _rng.randf() * TAU
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## Body, from the sim, for the gait. p is state.index_of(id), or -1.
func _read_body(walker: Walker, state: WorldState, p: int, info: Dictionary) -> void:
	if p == -1:
		walker.age = int(info.get("age", walker.age))
		var fallback: PackedByteArray = info.get("genome", PackedByteArray())
		if fallback.size() >= 10:
			walker.height = Genetics.express(fallback, "height")
			walker.build = Genetics.express(fallback, "build")
		return
	walker.age = People.age(state, p)
	walker.health = float(state.person_health[p])
	walker.mood = float(state.person_mood[p])
	walker.sick = state.person_sick[p] > 0
	walker.traits = People.traits_of(state, p)
	var genome := state.person_genomes[p]
	walker.height = Genetics.express(genome, "height")
	walker.build = Genetics.express(genome, "build")


## Gait speed plus seeded drift. Children and runs multiply it; the base is not one shared walk speed.
func _apply_speed(walker: Walker) -> void:
	_refresh_gait(walker)
	walker.speed = walker.gait_speed * _pace(walker)


func _refresh_gait(walker: Walker) -> void:
	if not walker.drift_ready:
		walker.drift_speed = float(Gait.drift(walker.id).speed)
		walker.drift_ready = true
	var sick := walker.activity == "sick" or walker.sick
	var load := _load_of(walker)
	var band := 0 if walker.age < Gait.CHILD_UNTIL else (2 if walker.age >= Gait.ELDER_AT else 1)
	var key := "%s|%s|%d|%s|%s|%d|%d|%.3f|%.3f|%s" % [walker.activity, walker.job, band, sick, load, int(walker.health), int(walker.mood), walker.height, walker.build, "|".join(walker.traits)]
	if key == walker.gait_key:
		return
	walker.gait_key = key
	var profile := Gait.profile(walker.age, walker.height, walker.build, walker.health, sick, walker.mood, walker.traits, load)
	walker.comfort = float(profile.comfort)
	walker.gait_speed = maxf(float(profile.speed) + walker.drift_speed, 0.05)


func _load_of(walker: Walker) -> String:
	if walker.phase != "to_drop":
		return ""
	var carry := String(CARRIES.get(walker.job, ""))
	if carry == "food" or carry == "wood" or carry == "stone":
		return carry
	return ""


## Playing children and a fight still run. The gait already speeds children, so infants are not multiplied again.
func _pace(walker: Walker) -> float:
	if walker.partner != -1 and walker.meet_kind == "fight":
		return RUN_SPEED / WALK_SPEED
	if walker.detained:
		return 0.7
	match walker.activity:
		"playing":
			return RUN_SPEED / WALK_SPEED
		"teaching":
			return 0.7
		"working":
			if walker.job == "guard":
				return 0.8
	return 1.0


func _camp_neighbors() -> Array:
	var neighbors: Array = []
	for walker: Walker in _walkers.values():
		if walker.dying > 0.0:
			continue
		var heading := walker.node.rotation.y
		var speed := 0.0
		if not walker.mover.is_empty():
			heading = float(walker.mover.heading)
			speed = Vector3(walker.mover.velocity).length()
		neighbors.append(Steering.mover(walker.node.position, heading, speed, Steering.BODY_RADIUS, maxf(walker.speed, 0.05), STEER_ACCEL, STEER_TURN, walker.comfort, walker.id))
	return neighbors


## Discs for finished buildings and the fire, plus wall capsules. Rebuilt only when that set changes.
func _camp_obstacles() -> Array:
	var stamp := _building_stamp()
	if _obstacles_ready and stamp == _obstacle_stamp:
		return _obstacles
	_obstacles_ready = true
	_obstacle_stamp = stamp
	var found: Array = [Steering.fire_obstacle(Vector3.ZERO)]
	var walled := false
	for id: int in _building_types:
		var type := String(_building_types[id])
		if not String(_building_keys.get(id, "")).ends_with("true"):
			continue
		if type in Buildings.WALLS:
			walled = true
			continue
		found.append(Steering.building_obstacle(type, _building_spots[id]))
	_lanes = null
	if walled:
		found.append_array(_wall_capsules())
		# Lanes reads only [inner, outer]. The outer ring is the wall, between RING_RADII[1] and [2].
		_lanes = Lanes.build(Vector3.ZERO, [RING_RADII[0], WALL_RADIUS], SPOKE_ANGLES, GATE_ANGLES)
	_obstacles = found
	return _obstacles


func _building_stamp() -> String:
	var ids: Array = _building_types.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: Variant in ids:
		var built := String(_building_keys.get(id, "")).ends_with("true")
		parts.append("%s:%s:%s" % [id, _building_types[id], built])
	return "|".join(parts)


## Capsules around the wall, open at the two gates. Pieces the mesh drops (a neighbor's side) are open too.
func _wall_capsules() -> Array:
	var pieces: Array = []
	var step := TAU / float(WALL_SEGMENTS)
	for i: int in WALL_SEGMENTS:
		var mid := step * (float(i) + 0.5)
		if _near_gate(mid):
			continue
		var a := _wall_point(step * float(i))
		var b := _wall_point(step * float(i + 1))
		if not _own_side((a + b) * 0.5, 0.2):
			continue
		pieces.append(Steering.wall_obstacle(a, b))
	return pieces


func _near_gate(angle: float) -> bool:
	for gate: float in GATE_ANGLES:
		if absf(angle_difference(angle, gate)) <= GATE_HALF:
			return true
	return false


func _wall_point(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, cos(angle)) * WALL_RADIUS


## Same side of the wall: straight to the target. Crossing it follows the lane through a gate.
func _aim(walker: Walker) -> Vector3:
	var goal := walker.target
	if _lanes == null:
		walker.lane_route.clear()
		return goal
	var here := walker.node.position
	var here_out := Vector2(here.x, here.z).length() > WALL_RADIUS
	var goal_out := Vector2(goal.x, goal.z).length() > WALL_RADIUS
	if here_out == goal_out:
		walker.lane_route.clear()
		return goal
	if walker.lane_route.is_empty() or walker.lane_goal.distance_squared_to(goal) > 0.09:
		walker.lane_route = _lanes.path(here, goal)
		walker.lane_goal = goal
	# The path starts where the walk began. Drop points already passed, or the next aim is behind them.
	_trim_route(here, walker.lane_route)
	return _next_lane_point(here, walker.lane_route, goal)


func _trim_route(here: Vector3, route: Array[Vector3]) -> void:
	while route.size() > 1:
		var a := route[0]
		var b := route[1]
		var da := Vector2(here.x - a.x, here.z - a.z).length()
		var db := Vector2(here.x - b.x, here.z - b.z).length()
		if da <= 0.45 or db + 0.05 < da:
			route.pop_front()
		else:
			break


func _next_lane_point(here: Vector3, route: Array[Vector3], goal: Vector3) -> Vector3:
	var here_r := Vector2(here.x, here.z).length()
	var leaving := here_r <= WALL_RADIUS
	var chosen := goal
	for at: Vector3 in route:
		var offset := Vector2(here.x - at.x, here.z - at.z)
		if offset.length() <= 0.4:
			continue
		# Outer-ring samples sit on the wall itself. Steer at the gate, not into a capsule.
		if _in_wall(at) and not _at_gate(at):
			continue
		chosen = at
		var at_r := Vector2(at.x, at.z).length()
		var beyond := (leaving and at_r > WALL_RADIUS + 0.05) or (not leaving and at_r < WALL_RADIUS - 0.05)
		if _at_gate(at) or beyond:
			break
		if offset.length() >= Steering.SLOW_RADIUS:
			break
	return Vector3(chosen.x, 0.0, chosen.z)


func _at_gate(at: Vector3) -> bool:
	var flat := Vector2(at.x, at.z)
	if absf(flat.length() - WALL_RADIUS) > 0.25:
		return false
	return _near_gate(atan2(flat.x, flat.y))


func _in_wall(at: Vector3) -> bool:
	return absf(Vector2(at.x, at.z).length() - WALL_RADIUS) <= Steering.WALL_THICKNESS + Steering.BODY_RADIUS


func _steer(walker: Walker, target: Vector3, neighbors: Array, obstacles: Array, delta: float) -> Dictionary:
	var node := walker.node
	if walker.mover.is_empty():
		walker.mover = Steering.mover(node.position, node.rotation.y, 0.0, Steering.BODY_RADIUS, walker.speed, STEER_ACCEL, STEER_TURN, walker.comfort, walker.id)
	else:
		walker.mover["position"] = node.position
		walker.mover["heading"] = node.rotation.y
		walker.mover["max_speed"] = walker.speed
		walker.mover["max_acceleration"] = STEER_ACCEL
		walker.mover["max_turn_rate"] = STEER_TURN
		walker.mover["comfort"] = walker.comfort
		walker.mover["radius"] = Steering.BODY_RADIUS
		walker.mover["id"] = walker.id
	var next: Dictionary = Steering.step(walker.mover, target, neighbors, obstacles, delta)
	walker.mover = next
	var pos := next.position as Vector3
	node.position = Vector3(pos.x, _ground(pos), pos.z)
	node.rotation.y = float(next.heading)
	return next


func _face(walker: Walker, at: Vector3) -> void:
	var look := at - walker.node.position
	if look.length() > 0.01:
		walker.node.rotation.y = atan2(look.x, look.z)


func _show_emote(walker: Walker) -> void:
	var style: Array = EMOTES.get(walker.meet_kind, EMOTES["chat"])
	if walker.emote == null:
		walker.emote = Label3D.new()
		walker.emote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		walker.emote.font_size = 64
		walker.emote.outline_size = 14
		walker.emote.outline_modulate = ToonMaterials.INK
		walker.emote.pixel_size = 0.004
		walker.emote.no_depth_test = true
		walker.node.add_child(walker.emote)
	walker.emote.text = String(style[0])
	walker.emote.modulate = style[1]
	walker.emote.visible = true
	walker.emote.position.y = VillagerArt.HEIGHT * float(walker.node.get_meta("growth", 1.0)) + 0.12


func _end_meeting(walker: Walker) -> void:
	walker.partner = -1
	walker.phase = ""
	if walker.emote:
		walker.emote.visible = false


# --- Banner, posters and monuments (AI-authored specs, see AssetDirector) -----------

const EMBLEM_SECONDS := 0.5 ## how often the banner, posters and monuments are checked
## Where propaganda goes up first: the masts and towers, the seats of power and control.
const POSTER_HOSTS: Array[String] = ["broadcast_tower", "surveillance_mast", "great_house", "barracks", "prison", "factory", "watchtower"]
const BANNER_SIZE := Vector2(0.26, 0.325)
const POSTER_SIZE := Vector2(0.23, 0.316)


## Keeps the banner by the fire (or the great house), a poster for every dark law in force and
## the statues' poses and temples' signs in step with their specs. Specs come from the world, or
## the offline writer while the AI is still writing them, so nothing waits.
func _sync_emblems(state: WorldState) -> void:
	var now := Time.get_ticks_msec()
	if now < _emblems_due:
		return
	_emblems_due = now + roundi(EMBLEM_SECONDS * 1000.0)
	var t := state.tribe_index(tribe_name)
	if t == -1:
		return
	_sync_banner(state)
	_sync_posters(state, t)
	_sync_monuments(state)


func _sync_banner(state: WorldState) -> void:
	var spec := AssetDirector.spec_or_offline(state, "heraldry", tribe_name)
	var houses := _built_of("great_house")
	var key := "%d|%s|%s" % [houses[0] if not houses.is_empty() else -1, spec.get("field", -1), spec.get("emblem", "")]
	if key == _banner_key or spec.is_empty():
		return
	_banner_key = key
	if _banner:
		_vanish(_banner)
	_banner = make_banner(spec)
	var spot: Vector3
	var facing: Vector3
	if houses.is_empty():
		# By the fire, on the side away from the island's middle.
		var out := Vector3(position.x, 0.0, position.z)
		facing = out.normalized() if out.length() > 0.5 else Vector3.BACK
		spot = facing.rotated(Vector3.UP, 0.6) * 0.78
	else:
		var house: Vector3 = _building_spots[houses[0]]
		facing = -house.normalized()
		spot = house + facing * 0.6 + facing.cross(Vector3.UP) * 0.36
	_banner.position = Vector3(spot.x, _ground(spot), spot.z)
	_banner.rotation.y = atan2(facing.x, facing.z)
	add_child(_banner)
	_pop_in(_banner)


## A pole with a crossbar and the banner hanging from it, painted on both faces.
static func make_banner(spec: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Banner"
	var wood := ToonMaterials.get_material(BuildingArt.TIMBER, 0.006)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.013
	pole.bottom_radius = 0.018
	pole.height = 1.08
	pole.radial_segments = 6
	holder.add_child(_part(pole, wood, Vector3(0.0, 0.54, 0.0)))
	var bar := CylinderMesh.new()
	bar.top_radius = 0.009
	bar.bottom_radius = 0.009
	bar.height = BANNER_SIZE.x + 0.06
	bar.radial_segments = 5
	holder.add_child(_part(bar, wood, Vector3(0.0, 0.99, 0.02), Vector3(0.0, 0.0, PI / 2.0)))
	var knob := SphereMesh.new()
	knob.radius = 0.028
	knob.height = 0.056
	holder.add_child(_part(knob, ToonMaterials.get_material(BuildingArt.GOLD, 0.006), Vector3(0.0, 1.1, 0.0)))
	var cloth := QuadMesh.new()
	cloth.size = BANNER_SIZE
	var painted := EmblemArt.material(EmblemArt.banner_texture(spec))
	var middle := 0.98 - BANNER_SIZE.y / 2.0
	holder.add_child(_part(cloth, painted, Vector3(0.0, middle, 0.03)))
	holder.add_child(_part(cloth, painted, Vector3(0.0, middle, 0.026), Vector3(0.0, PI, 0.0)))
	return holder


func _sync_posters(state: WorldState, t: int) -> void:
	var specs: Array[Dictionary] = []
	for law: String in Society.laws_of(state, t):
		if Laws.is_dystopian(law):
			var spec := AssetDirector.spec_or_offline(state, "poster", "%s|%s" % [tribe_name, law])
			if not spec.is_empty():
				specs.append(spec)
	var spots := _poster_spots(specs.size())
	var parts := PackedStringArray()
	for k: int in specs.size():
		parts.append("%s|%s|%s|%s|%s" % [specs[k].get("slogan", ""), specs[k].get("ground", 0), specs[k].get("ink", 0), specs[k].get("emblem", ""), spots[k]])
	var key := "\n".join(parts)
	if key == _posters_key:
		return
	_posters_key = key
	for board: Node3D in _posters:
		_vanish(board)
	_posters.clear()
	for k: int in specs.size():
		var spot: Array = spots[k]
		var board := make_poster(specs[k])
		var at: Vector3 = spot[0]
		var facing: Vector3 = spot[1]
		board.position = Vector3(at.x, _ground(at), at.z)
		board.rotation.y = atan2(facing.x, facing.z)
		add_child(board)
		_pop_in(board)
		_posters.append(board)


## Where n posters go, as [spot, the way they face]: in front of the masts, towers and seats of
## power first, then along the inside of the wall, then on boards around the fire.
func _poster_spots(n: int) -> Array[Array]:
	var spots: Array[Array] = []
	for type: String in POSTER_HOSTS:
		for id: int in _built_of(type):
			var at: Vector3 = _building_spots[id]
			var facing := -at.normalized()
			var depth: float = (BuildingArt.SIZES[type] as Vector3).y + 0.14
			spots.append([at + facing * depth + facing.cross(Vector3.UP) * 0.2, facing])
	var walled := not _built_of("stone_wall").is_empty() or not _built_of("palisade").is_empty()
	for k: int in (6 if walled else 0):
		var on_wall := Vector3.FORWARD.rotated(Vector3.UP, 0.5 + TAU * k / 6.0) * (WALL_RADIUS - 0.16)
		if _own_side(on_wall, 0.2) and shape.is_buildable(position.x + on_wall.x, position.z + on_wall.z, 0.1):
			spots.append([on_wall, -on_wall.normalized()])
	var k := 0
	while spots.size() < n:
		var by_fire := Vector3.FORWARD.rotated(Vector3.UP, 2.2 + k * 0.62) * 0.92
		spots.append([by_fire, -by_fire.normalized()])
		k += 1
	return spots.slice(0, n)


## A painted board on two posts, its slogan lettered in the band at its foot.
static func make_poster(spec: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Poster"
	var base := 0.17
	var wood := ToonMaterials.get_material(BuildingArt.TIMBER, 0.006)
	var post := CylinderMesh.new()
	post.top_radius = 0.009
	post.bottom_radius = 0.011
	post.height = base + POSTER_SIZE.y
	post.radial_segments = 5
	for x: float in [-0.085, 0.085]:
		holder.add_child(_part(post, wood, Vector3(x, post.height / 2.0, -0.016)))
	var back := BoxMesh.new()
	back.size = Vector3(POSTER_SIZE.x + 0.02, POSTER_SIZE.y + 0.02, 0.016)
	var middle := base + POSTER_SIZE.y / 2.0
	holder.add_child(_part(back, ToonMaterials.get_material(BuildingArt.IRON, 0.006), Vector3(0.0, middle, -0.002)))
	var face := QuadMesh.new()
	face.size = POSTER_SIZE
	holder.add_child(_part(face, EmblemArt.material(EmblemArt.poster_texture(spec)), Vector3(0.0, middle, 0.0075)))
	var words := Label3D.new()
	words.text = String(spec.get("slogan", "")).to_upper()
	words.font = UiStyle.font("caps")
	words.font_size = 22
	words.pixel_size = 0.0008
	words.outline_size = 0
	words.width = (POSTER_SIZE.x - 0.025) / words.pixel_size
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.modulate = ArtPalette.color(int(spec.get("ground", 30)))
	words.position = Vector3(0.0, middle + POSTER_SIZE.y / 2.0 - POSTER_SIZE.y * 71.5 / 88.0, 0.011)
	holder.add_child(words)
	return holder


## Statues take the pose their spec gives the ruler; temples show their holy sign on the pediment.
## A building rebuilt by _sync_buildings loses these, so they are checked every time.
func _sync_monuments(state: WorldState) -> void:
	for type: String in MonumentKind.TYPES:
		for id: int in _built_of(type):
			var model := (_buildings[id] as Node3D).get_node_or_null("Model") as Node3D
			if model == null:
				continue
			var spec := AssetDirector.spec_or_offline(state, "monument", str(id))
			if type == "statue":
				var pose := String(spec.get("pose", "raised_fist"))
				var figure := model.get_node_or_null("Figure") as Node3D
				if figure and String(figure.get_meta("pose", "")) != pose:
					model.remove_child(figure)
					figure.queue_free()
					model.add_child(BuildingArt.statue_figure(pose))
			else:
				var icon := String(spec.get("iconography", ""))
				var plaque := model.get_node_or_null("Icon") as Node3D
				if icon and (plaque == null or String(plaque.get_meta("icon", "")) != icon):
					if plaque:
						model.remove_child(plaque)
						plaque.queue_free()
					model.add_child(make_temple_sign(icon))


## A temple's holy sign: a painted plaque on the front of its pediment, the model's "Icon" child.
static func make_temple_sign(icon: String) -> MeshInstance3D:
	var tile := QuadMesh.new()
	tile.size = Vector2(0.12, 0.12)
	var holy_sign := _part(tile, EmblemArt.material(EmblemArt.texture(EmblemArt.plaque_svg(icon))), Vector3(0.0, 0.79, 0.332))
	holy_sign.name = "Icon"
	holy_sign.set_meta("icon", icon)
	return holy_sign


## Finished buildings of a type in this village, oldest first.
func _built_of(type: String) -> Array[int]:
	var found: Array[int] = []
	for id: int in _building_types:
		if _building_types[id] == type and String(_building_keys.get(id, "")).ends_with("true"):
			found.append(id)
	found.sort()
	return found


static func _part(mesh: Mesh, material: Material, at: Vector3, turn: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	part.rotation = turn
	return part


# --- Layout -------------------------------------------------------------------------

## Where a building slot sits around the fire, nudged around its ring until it's on dry land.
func _slot_spot(slot: int) -> Vector3:
	if _slot_spots.has(slot):
		return _slot_spots[slot]
	var spot := Vector3.ZERO
	if slot == -3:
		var angle := _rng.randf() * TAU
		spot = Vector3(cos(angle), 0.0, sin(angle)) * (RING_RADII[2] + 0.6)
	elif slot >= 0:
		var ring := Buildings.ring_of(slot)
		var size := Buildings.RING_SIZES[ring]
		var index := slot - Buildings.ring_start(ring)
		var base := TAU * index / size + ring * 0.37
		var fallback := Vector3.INF
		for radius: float in [RING_RADII[ring], RING_RADII[ring] * 0.88, RING_RADII[ring] * 0.76]:
			for attempt: int in 16:
				var angle := base + (attempt + 1) / 2 * (TAU / size) * 0.5 * (1 if attempt % 2 == 0 else -1)
				spot = Vector3(cos(angle), 0.0, sin(angle)) * radius
				if not shape.is_buildable(position.x + spot.x, position.z + spot.z, 0.4):
					continue
				if fallback == Vector3.INF:
					fallback = spot
				if _has_room(spot, ring):
					fallback = spot
					break
			if _has_room(fallback, ring):
				break
		if fallback != Vector3.INF:
			spot = fallback
	_slot_spots[slot] = spot
	return spot


## True if a spot is clear of the buildings already placed, on this village's side of every
## neighbor (camps can sit closer than the rings reach on a small island) and, on the outer
## ring, clear of the graveyard.
func _has_room(spot: Vector3, ring: int) -> bool:
	if spot == Vector3.INF:
		return false
	for other: Vector3 in _slot_spots.values():
		if other.distance_to(spot) < (0.8 if ring < 2 else 1.05):
			return false
	if ring == 0:
		return true
	if ring == 3 and spot.distance_to(_grave_spot(20)) < 1.9:
		return false
	return _own_side(spot, 0.6)


## True if a point is nearer this camp's fire than any other camp spot's, by a margin.
func _own_side(spot: Vector3, margin: float) -> bool:
	var here := Vector2(spot.x, spot.z)
	for i: int in IslandShape.CAMP_SLOTS:
		var camp := shape.camp_slot(i) - position
		var other := Vector2(camp.x, camp.z)
		if other.length() > 0.5 and other.distance_to(here) < here.length() + margin:
			return false
	return true


## Graves sit in rows on the far side of the village, away from the island's middle.
func _grave_spot(index: int) -> Vector3:
	var out := Vector2(position.x, position.z)
	var away := out.normalized() if out.length() > 0.5 else Vector2(1.0, 0.0)
	var side := Vector2(-away.y, away.x)
	var row := index / 8
	var column := index % 8 - 3.5
	var flat := away * (RING_RADII[2] + 0.7 + row * 0.38) + side * column * 0.34
	var spot := Vector3(flat.x, 0.0, flat.y)
	if not shape.is_buildable(position.x + spot.x, position.z + spot.z, 0.2):
		flat = -away * (RING_RADII[2] + 0.7 + row * 0.38) + side * column * 0.34
		spot = Vector3(flat.x, 0.0, flat.y)
	return spot


## Ground height in this settlement's local space.
func _ground(local: Vector3) -> float:
	return shape.height_at(position.x + local.x, position.z + local.z) - position.y


func _pop_in(node: Node3D) -> void:
	var final_scale := node.scale
	node.scale = Vector3.ONE * 0.01
	create_tween().tween_property(node, "scale", final_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _vanish(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * 0.01, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(node.queue_free)


## Shrinks the whole village away, then frees it.
func vanish() -> void:
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
