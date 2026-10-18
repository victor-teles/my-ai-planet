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
	var dying := 0.0 ## counts up once they have died
	var status := "" ## "", "noble" or "bonded"
	var detained := false
	var patrol := false ## a guard walking the rounds
	var patrol_angle := 0.0


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
	_sync_buildings(state)
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
		var key := "%s|%s|%s" % [type, BuildingArt.variant(type, _age), built]
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
	var model := BuildingArt.wall(type, WALL_RADIUS, tint) if wall else BuildingArt.make(type, tint, _age)
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


func _sync_person(id: int, info: Dictionary, arrivals: Dictionary, status: String, detained: bool) -> void:
	var age := int(info["age"])
	var key := "%s|%s" % [VillagerArt.looks_key(age, info["chief"]), status]
	var walker: Walker = _walkers.get(id)
	if walker == null:
		walker = Walker.new()
		walker.id = id
		_walkers[id] = walker
	if walker.key != key:
		var looks := VillagerArt.dress(VillagerArt.appearance_of(info["genome"], id, info["female"], age, info["chief"], tint), status)
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
		VillagerArt.set_tool(walker.node, "")
		walker.job = ""
	if walker.detained != detained:
		walker.detained = detained
		walker.job = ""
		walker.node.visible = true
		if walker.partner == -1:
			walker.phase = ""
	if walker.activity != info["activity"] or walker.job != info["job"] or walker.home != int(info["home"]):
		walker.activity = info["activity"]
		walker.job = info["job"]
		walker.home = int(info["home"])
		walker.mother = int(info["mother"])
		if walker.partner == -1:
			walker.phase = ""
		var working := walker.activity == "working" and not walker.detained
		VillagerArt.set_tool(walker.node, String(TOOLS.get(walker.job, "")) if working else "")
		if not working:
			VillagerArt.set_carry(walker.node, "")
		# Guards wear their helmets and officials their caps on duty or off; not in a cell.
		var gear := "" if walker.detained else String({"guard": "helmet", "official": "cap"}.get(walker.job, ""))
		VillagerArt.set_headgear(walker.node, gear, BRONZE if _age < 2 else STEEL, tint)


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
		walker.speed = WALK_SPEED if kind != "fight" else RUN_SPEED


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
		if walker.dying > 0.0:
			_die_step(walker, delta)
		else:
			_step(walker, delta, time)


func _die_step(walker: Walker, delta: float) -> void:
	walker.dying += delta
	VillagerArt.set_lying(walker.node, clampf(walker.dying / 0.8, 0.0, 1.0))
	if walker.dying > 1.6 and _walkers.get(walker.id) == walker:
		for keep: Node3D in [_focus_ring, _name_tag]:
			if keep and keep.get_parent() == walker.node:
				walker.node.remove_child(keep)
		_walkers.erase(walker.id)
		_vanish(walker.node)


func _step(walker: Walker, delta: float, time: float) -> void:
	var node := walker.node
	if walker.phase.is_empty():
		_plan(walker)
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
	var moving := distance > 0.04 and walker.phase not in ["work", "rest", "lie", "meet", "drop"]
	walker.walking = move_toward(walker.walking, 1.0 if moving else 0.0, delta * 3.0)
	VillagerArt.set_walking(node, walker.walking)
	if moving:
		var step := to_target.normalized() * minf(walker.speed * maxf(walker.walking, 0.2) * delta, distance)
		node.position += step
		node.position.y = _ground(node.position)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(to_target.x, to_target.z), minf(delta * 8.0, 1.0))
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
	walker.speed = WALK_SPEED
	walker.patrol = false
	if walker.detained:
		_hold(walker)
		return
	match walker.activity:
		"infant":
			walker.phase = "follow"
			walker.speed = WALK_SPEED * 1.4
			walker.timer = 0.5
		"playing":
			# Children run about the whole village, and sometimes tag along with a parent.
			walker.phase = "wander"
			walker.speed = RUN_SPEED
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
			walker.speed = WALK_SPEED * 0.7
			walker.timer = 30.0
		"working":
			walker.phase = "to_work"
			walker.target = _work_spot(walker)
			walker.timer = 40.0
			if walker.job == "guard":
				walker.speed = WALK_SPEED * 0.8
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
	walker.speed = WALK_SPEED * 0.7
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
