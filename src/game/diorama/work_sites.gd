class_name WorkSites
extends RefCounted
## Where work happens on the island: the trees woodcutters fell, the rocks quarriers break, the
## bushes foragers pick, the shores fishers wade, and the wild edges hunters stalk. Villagers ask
## for the nearest spot of a kind. Trees standing where a tribe builds are felled to stumps.

var shape: IslandShape
var trees: Array[Node3D] = []
var rocks: Array[Node3D] = []
var bushes: Array[Node3D] = []
var springs: Array[Vector3] = []


func _init(island: IslandShape) -> void:
	shape = island


func nearest_tree(from: Vector3) -> Vector3:
	return _nearest(trees.filter(func(tree: Node3D) -> bool: return tree.visible), from, from + Vector3(2.0, 0.0, 0.0))


func nearest_rock(from: Vector3) -> Vector3:
	return _nearest(rocks.filter(func(rock: Node3D) -> bool: return rock.visible), from, from + Vector3(-2.0, 0.0, 1.0))


## One of the few bushes closest to a spot, picked by the caller's dice so foragers spread out.
func bush_near(from: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var standing := bushes.filter(func(bush: Node3D) -> bool: return bush.visible)
	if standing.is_empty():
		return from + Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
	standing.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.distance_squared_to(from) < b.position.distance_squared_to(from))
	return (standing[rng.randi_range(0, mini(6, standing.size() - 1))] as Node3D).position


## A spot on the shore of the pond (water 0) or a spring.
func shore(water: int, from: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var center: Vector3
	var radius: float
	if water <= 0 or water - 1 >= springs.size():
		center = Vector3(shape.pond_center.x, 0.0, shape.pond_center.y)
		radius = shape.pond_radius * 1.05
	else:
		center = springs[water - 1]
		radius = IslandShape.SPRING_RADIUS * 1.15
	var toward := Vector2(from.x - center.x, from.z - center.z).angle() + rng.randf_range(-0.9, 0.9)
	var point := Vector3(center.x + cos(toward) * radius, 0.0, center.z + sin(toward) * radius)
	return shape.surface_point(point.x, point.z)


## A spot out in the wilds toward the island's edge, away from the camp.
func hunting_ground(from: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var angle := atan2(from.z, from.x) + rng.randf_range(-1.0, 1.0)
	var radius := shape.edge_radius(angle) * rng.randf_range(0.7, 0.82)
	return shape.surface_point(cos(angle) * radius, sin(angle) * radius)


## Clears the land within a radius: trees are felled (leaving stumps, unless the land was settled
## before anyone watched), bushes and rocks taken away.
func clear(at: Vector3, radius: float, stumps: bool = true) -> void:
	for tree: Node3D in trees:
		if tree.visible and Vector2(tree.position.x - at.x, tree.position.z - at.z).length() < radius:
			if stumps:
				fell(tree)
			else:
				tree.visible = false
	for thing: Node3D in bushes + rocks:
		if thing.visible and Vector2(thing.position.x - at.x, thing.position.z - at.z).length() < radius * 0.85:
			thing.visible = false


func fell(tree: Node3D) -> void:
	tree.visible = false
	var stump := Kit.prop("stump_round")
	stump.scale *= 0.6
	stump.position = tree.position
	tree.get_parent().add_child(stump)


func _nearest(nodes: Array, from: Vector3, fallback: Vector3) -> Vector3:
	var best := fallback
	var best_distance := INF
	for node: Node3D in nodes:
		var distance := node.position.distance_squared_to(from)
		if distance < best_distance:
			best = node.position
			best_distance = distance
	return best
