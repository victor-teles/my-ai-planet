class_name IslandShape
extends RefCounted
## The floating island's shape: terrain height, outline, pond and camp spots.
## Shared by the mesh builder and everything placed on the island, so props always sit on the ground,
## and by the sim, which founds no more tribes than there are camp spots. Pure math, no rendering.
## The world recipe (WorldGen, "island") sets its size, how ragged its outline and how hilly its
## top, where the pond lies and how many springs it has; the seed fills in the details.

const WATER_LEVEL := 0.42
const CAMP_SLOTS := 12
const CAMP_SPACING := 6.9 ## villages grow to about this across
const MIN_SPACING := 0.85 ## small islands pack camps closer, but never so close that grown towns collide
const CAMP_MARGIN := 1.5 ## how far a camp's center keeps from the shore and the water
const SPRING_RADIUS := 0.95
const SPRING_DEPTH := 0.42

var biome := "meadow"
var radius := 10.0
var roughness := 0.22 ## how far the outline wanders in and out
var hills := 0.6 ## height of the bumps on top
var pond_center := Vector2(-3.4, 2.6)
var pond_radius := 2.3
var spring_count := 4 ## water sources after the pond (water 1..N in WorldState)

var _bumps := FastNoiseLite.new()
var _outline := FastNoiseLite.new()
var _camp_slots: Array[Vector3] = []
var _spring_spots: Array[Vector3] = []


func _init(world: Dictionary, seed_value: int) -> void:
	var island: Dictionary = world.get("island", {})
	biome = String(world.get("biome", biome))
	radius = float(island.get("radius", radius))
	roughness = float(island.get("roughness", roughness))
	hills = float(island.get("hills", hills))
	var pond: Array = island.get("pond", [pond_center.x, pond_center.y])
	pond_center = Vector2(float(pond[0]), float(pond[1]))
	pond_radius = float(island.get("pond_radius", pond_radius))
	spring_count = int(island.get("springs", spring_count))
	_bumps.seed = seed_value
	_bumps.frequency = 0.09
	_bumps.fractal_octaves = 3
	_outline.seed = seed_value + 1
	_outline.frequency = 0.9
	_camp_slots = _find_camp_slots()
	_spring_spots = _find_spring_spots()


## Distance from the center to the island's edge in a direction.
func edge_radius(angle: float) -> float:
	return radius * (0.86 + roughness * _outline.get_noise_2d(cos(angle) * 2.0, sin(angle) * 2.0))


## Terrain height, including the dips the springs sit in.
func height_at(x: float, z: float) -> float:
	var height := _base_height(x, z)
	for spot: Vector3 in _spring_spots:
		var d := Vector2(spot.x, spot.z).distance_to(Vector2(x, z)) / SPRING_RADIUS
		if d < 1.0:
			height -= SPRING_DEPTH * (1.0 - smoothstep(0.0, 1.0, d))
	return height


func _base_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length() / radius
	var dome := 1.0 * (1.0 - r * r)
	var bumps := hills * 0.8 * _bumps.get_noise_2d(x, z)
	var pond := Vector2(x, z).distance_to(pond_center) / pond_radius
	var dip := -0.95 * (1.0 - smoothstep(0.0, 1.0, pond))
	return dome + bumps + dip


func surface_point(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## True on land that's comfortably away from the edge and the water.
func is_buildable(x: float, z: float, margin: float = 1.6) -> bool:
	var angle := atan2(z, x)
	if Vector2(x, z).length() > edge_radius(angle) - margin:
		return false
	return height_at(x, z) > WATER_LEVEL + 0.15


## How many camps fit on the island. The sim founds no more tribes than this.
func camp_count() -> int:
	return _camp_slots.size()


## Where tribe camps go, in the order they're handed out (the first is near the center).
func camp_slot(index: int) -> Vector3:
	return _camp_slots[index % _camp_slots.size()]


func is_near_camp(x: float, z: float, distance: float) -> bool:
	for slot: Vector3 in _camp_slots + _spring_spots:
		if Vector2(slot.x, slot.z).distance_to(Vector2(x, z)) < distance:
			return true
	return false


## Where the springs bubble up, away from the camps and the pond. The point is on the rim
## of the spring's dip, which is where its water surface sits when full.
func spring_spot(index: int) -> Vector3:
	return _spring_spots[index % _spring_spots.size()]


## Walks around the island at about two thirds of its radius, keeping spots clear of the camps,
## the pond and each other. Small or crowded islands get further passes, nearer the middle or
## the rim and with less room between, so every spring the recipe asks for gets its own spot.
func _find_spring_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var passes: Array[Vector2] = [Vector2(0.62, 2.6), Vector2(0.5, 2.3), Vector2(0.74, 2.2), Vector2(0.4, 2.0), Vector2(0.8, 1.6)]
	for pass_rule: Vector2 in passes:
		for i: int in 72:
			if spots.size() >= spring_count:
				return spots
			var angle := TAU * i / 72.0 + 0.3
			var distance := edge_radius(angle) * pass_rule.x
			var x := cos(angle) * distance
			var z := sin(angle) * distance
			if not is_buildable(x, z, 1.4) or Vector2(x, z).distance_to(pond_center) < pond_radius + 1.5:
				continue
			var crowded := false
			for other: Vector3 in _camp_slots + spots:
				if Vector2(other.x, other.z).distance_to(Vector2(x, z)) < pass_rule.y:
					crowded = true
					break
			if not crowded:
				spots.append(Vector3(x, _base_height(x, z), z))
	if spots.is_empty():
		spots.append(Vector3(pond_center.x, _base_height(pond_center.x, pond_center.y), pond_center.y))
	return spots


## Golden-angle spiral from the center, keeping only buildable spots far enough apart. Smaller
## islands pack their camps a little closer rather than run out of room.
func _find_camp_slots() -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var spacing := CAMP_SPACING * clampf(radius / 10.0, 0.9, 1.1)
	while true:
		slots = _spiral_slots(spacing)
		if slots.size() >= 5 or spacing < CAMP_SPACING * MIN_SPACING:
			break
		spacing *= 0.92
	assert(not slots.is_empty(), "Island has no room for camps")
	return slots


func _spiral_slots(spacing: float) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i: int in 400:
		if slots.size() >= CAMP_SLOTS:
			break
		var distance := 0.8 + 0.42 * sqrt(float(i)) * 1.4
		var x := cos(i * golden_angle) * distance
		var z := sin(i * golden_angle) * distance
		if not is_buildable(x, z, CAMP_MARGIN):
			continue
		var crowded := false
		for slot: Vector3 in slots:
			if Vector2(slot.x, slot.z).distance_to(Vector2(x, z)) < spacing:
				crowded = true
				break
		if not crowded:
			slots.append(surface_point(x, z))
	return slots
