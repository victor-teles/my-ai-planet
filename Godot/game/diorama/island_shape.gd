class_name IslandShape
extends RefCounted
## The floating island's shape: terrain height, outline, pond and camp spots.
## Shared by the mesh builder and everything placed on the island, so props always sit on the ground.

const RADIUS := 10.0
const POND_CENTER := Vector2(-3.4, 2.6)
const POND_RADIUS := 2.3
const WATER_LEVEL := 0.42
const CAMP_SLOTS := 12
const SPRING_SPOTS := 4
const SPRING_RADIUS := 0.95
const SPRING_DEPTH := 0.42

var _bumps := FastNoiseLite.new()
var _outline := FastNoiseLite.new()
var _camp_slots: Array[Vector3] = []
var _spring_spots: Array[Vector3] = []


func _init(seed_value: int) -> void:
	_bumps.seed = seed_value
	_bumps.frequency = 0.09
	_bumps.fractal_octaves = 3
	_outline.seed = seed_value + 1
	_outline.frequency = 0.9
	_camp_slots = _find_camp_slots()
	_spring_spots = _find_spring_spots()


## Distance from the center to the island's edge in a direction.
func edge_radius(angle: float) -> float:
	return RADIUS * (0.86 + 0.22 * _outline.get_noise_2d(cos(angle) * 2.0, sin(angle) * 2.0))


## Terrain height, including the dips the springs sit in.
func height_at(x: float, z: float) -> float:
	var height := _base_height(x, z)
	for spot: Vector3 in _spring_spots:
		var d := Vector2(spot.x, spot.z).distance_to(Vector2(x, z)) / SPRING_RADIUS
		if d < 1.0:
			height -= SPRING_DEPTH * (1.0 - smoothstep(0.0, 1.0, d))
	return height


func _base_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length() / RADIUS
	var dome := 1.0 * (1.0 - r * r)
	var bumps := 0.5 * _bumps.get_noise_2d(x, z)
	var pond := Vector2(x, z).distance_to(POND_CENTER) / POND_RADIUS
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


## Walks around the island at two thirds of its radius, keeping spots clear of camps and each other.
func _find_spring_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for i: int in 72:
		if spots.size() >= SPRING_SPOTS:
			break
		var angle := TAU * i / 72.0 + 0.3
		var radius := edge_radius(angle) * 0.62
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		if not is_buildable(x, z, 1.4) or Vector2(x, z).distance_to(POND_CENTER) < POND_RADIUS + 1.5:
			continue
		var crowded := false
		for other: Vector3 in _camp_slots + spots:
			if Vector2(other.x, other.z).distance_to(Vector2(x, z)) < 2.6:
				crowded = true
				break
		if not crowded:
			spots.append(Vector3(x, _base_height(x, z), z))
	if spots.is_empty():
		spots.append(Vector3(POND_CENTER.x, _base_height(POND_CENTER.x, POND_CENTER.y), POND_CENTER.y))
	return spots


## Golden-angle spiral from the center, keeping only buildable spots far enough apart.
func _find_camp_slots() -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i: int in 400:
		if slots.size() >= CAMP_SLOTS:
			break
		var radius := 0.8 + 0.42 * sqrt(float(i)) * 1.4
		var x := cos(i * golden_angle) * radius
		var z := sin(i * golden_angle) * radius
		if not is_buildable(x, z, 2.2):
			continue
		var crowded := false
		for slot: Vector3 in slots:
			if Vector2(slot.x, slot.z).distance_to(Vector2(x, z)) < 4.0:
				crowded = true
				break
		if not crowded:
			slots.append(surface_point(x, z))
	assert(not slots.is_empty(), "Island has no room for camps")
	return slots
