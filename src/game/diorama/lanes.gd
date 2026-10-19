class_name Lanes
extends RefCounted
## Ring streets, the spokes between them, and the gates in the outer wall.
## path() is A* over that graph (a few dozen nodes). An outside goal is reached through a
## gate node, not a chord across the wall. wander_waypoints() bends a walk around a blocked disc.
## Angles use Steering's heading: 0 is +Z, increasing toward +X.

var center := Vector3.ZERO
var inner_radius := 0.0
var outer_radius := 0.0
var nodes: Array[Vector3] = []
var gates: Array[Vector3] = []

var _links: Array[PackedInt32Array] = []
var _is_gate: PackedByteArray = PackedByteArray()


## ring_radii is [inner, outer]. spoke_angles join the rings; gate_angles open the outer ring.
static func build(at: Vector3, ring_radii: Array, spoke_angles: Array, gate_angles: Array) -> Lanes:
	var lanes := Lanes.new()
	lanes._build(at, ring_radii, spoke_angles, gate_angles)
	return lanes


## Polyline from `from` to `to` along the lanes. Outside the wall, it includes a gate node.
func path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var flat_from := _flat(from)
	var flat_to := _flat(to)
	if nodes.is_empty():
		return [flat_from, flat_to]
	var start_links := _attach(flat_from)
	var goal_links := _attach(flat_to)
	if start_links.is_empty() or goal_links.is_empty():
		return [flat_from, flat_to]
	var count := nodes.size()
	var start := count
	var goal := count + 1
	var open: Array[int] = [start]
	var in_open := PackedByteArray()
	in_open.resize(count + 2)
	in_open[start] = 1
	var closed := PackedByteArray()
	closed.resize(count + 2)
	var gscore := PackedFloat32Array()
	gscore.resize(count + 2)
	var came := PackedInt32Array()
	came.resize(count + 2)
	for i: int in count + 2:
		gscore[i] = INF
		came[i] = -1
	gscore[start] = 0.0

	while not open.is_empty():
		var best_i := 0
		var best_f := INF
		var best_id := 2147483647
		for n: int in open.size():
			var id: int = open[n]
			var estimate := gscore[id] + _at(id, flat_from, flat_to, count).distance_to(flat_to)
			if estimate < best_f - 0.00001 or (absf(estimate - best_f) <= 0.00001 and id < best_id):
				best_f = estimate
				best_i = n
				best_id = id
		var current := best_id
		open.remove_at(best_i)
		if current == goal:
			return _reconstruct(came, start, goal, flat_from, flat_to, count)
		if closed[current] == 1:
			continue
		closed[current] = 1
		for next_id: int in _neighbors_of(current, start, goal, start_links, goal_links):
			if closed[next_id] == 1:
				continue
			var step_cost := _at(current, flat_from, flat_to, count).distance_to(_at(next_id, flat_from, flat_to, count))
			var tentative := gscore[current] + step_cost
			if tentative + 0.00001 < gscore[next_id]:
				gscore[next_id] = tentative
				came[next_id] = current
				if in_open[next_id] == 0:
					open.append(next_id)
					in_open[next_id] = 1
	return [flat_from, flat_to]


## Points so the polyline from `from` to `to` misses blocked discs (a tree or a rock).
## Adds 1 or 2 points when the straight walk is blocked; a clear walk is just the two ends.
## Deterministic: no RNG.
static func wander_waypoints(from: Vector3, to: Vector3, blocks: Array) -> Array[Vector3]:
	var a := Vector3(from.x, 0.0, from.z)
	var b := Vector3(to.x, 0.0, to.z)
	var hit := _first_block(a, b, blocks)
	if hit < 0:
		return [a, b]
	var block: Dictionary = blocks[hit]
	var around := _detour(a, b, Vector3(block.center.x, 0.0, block.center.z), float(block.radius), blocks)
	var route: Array[Vector3] = [a]
	route.append_array(around)
	route.append(b)
	return route


func _build(at: Vector3, ring_radii: Array, spoke_angles: Array, gate_angles: Array) -> void:
	center = _flat(at)
	inner_radius = float(ring_radii[0])
	outer_radius = float(ring_radii[1])
	var spokes := _angles_of(spoke_angles)
	var gate_list := _angles_of(gate_angles)
	var angles := _ring_angles(spokes, gate_list)
	var count := angles.size()
	nodes = []
	gates = []
	_is_gate = PackedByteArray()
	nodes.append(center)
	_is_gate.append(0)
	for k: int in count:
		nodes.append(center + _dir(float(angles[k])) * inner_radius)
		_is_gate.append(0)
	for k: int in count:
		var angle := float(angles[k])
		var pos := center + _dir(angle) * outer_radius
		nodes.append(pos)
		if _near_any(angle, gate_list, 0.045):
			_is_gate.append(1)
			gates.append(pos)
		else:
			_is_gate.append(0)
	var raw: Array[Array] = []
	raw.resize(nodes.size())
	for i: int in nodes.size():
		raw[i] = []
	for k: int in count:
		var angle := float(angles[k])
		var inner_i := 1 + k
		var outer_i := 1 + count + k
		var next_k := (k + 1) % count
		_join(raw, inner_i, 1 + next_k)
		_join(raw, outer_i, 1 + count + next_k)
		# Spokes, and a radial step at each gate, keep both rings one connected inside.
		if _near_any(angle, spokes, 0.045) or _near_any(angle, gate_list, 0.045):
			_join(raw, 0, inner_i)
			_join(raw, inner_i, outer_i)
	_links = []
	for row: Array in raw:
		var packed := PackedInt32Array()
		for id: int in row:
			packed.append(id)
		_links.append(packed)


## 12 samples plus the caller's spokes and gates, folded into one sorted ring. About 20 to 40 nodes.
static func _ring_angles(spokes: PackedFloat32Array, gate_list: PackedFloat32Array) -> PackedFloat32Array:
	var list: Array[float] = []
	var steps := 12
	for i: int in steps:
		list.append(TAU * float(i) / float(steps))
	for angle: float in spokes:
		list.append(angle)
	for angle: float in gate_list:
		list.append(angle)
	var unique: Array[float] = []
	for angle: float in list:
		var wrapped := fposmod(angle, TAU)
		if wrapped > TAU - 0.0001:
			wrapped = 0.0
		if not _near_any(wrapped, PackedFloat32Array(unique), 0.03):
			unique.append(wrapped)
	unique.sort()
	return PackedFloat32Array(unique)


static func _angles_of(angles: Array) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	for i: int in angles.size():
		packed.append(fposmod(float(angles[i]), TAU))
	return packed


func _attach(point: Vector3) -> Array[int]:
	var picked: Array[int] = []
	var dists: Array[float] = []
	for i: int in nodes.size():
		if _blocked_link(point, nodes[i], i):
			continue
		var dist := _flat(point).distance_to(_flat(nodes[i]))
		var place := picked.size()
		for k: int in picked.size():
			if dist < dists[k] - 0.0001 or (absf(dist - dists[k]) <= 0.0001 and i < picked[k]):
				place = k
				break
		picked.insert(place, i)
		dists.insert(place, dist)
		if picked.size() > 4:
			picked.resize(4)
			dists.resize(4)
	var chosen: Array[int] = []
	if picked.is_empty():
		return chosen
	for k: int in picked.size():
		if chosen.size() >= 3:
			break
		if chosen.size() >= 1 and dists[k] > dists[0] + 1.25:
			break
		chosen.append(picked[k])
	return chosen


## An outside point may touch a gate, never a plain inside node, and no link may cut the camp.
func _blocked_link(point: Vector3, node: Vector3, index: int) -> bool:
	var point_out := _radius_of(point) > outer_radius + 0.03
	var node_out := _radius_of(node) > outer_radius + 0.03
	var gate := _is_gate[index] == 1
	if point_out and not node_out and not gate:
		return true
	if not point_out and node_out and not gate:
		return true
	return _cuts_wall(point, node)


func _cuts_wall(a: Vector3, b: Vector3) -> bool:
	var a_out := _radius_of(a) > outer_radius + 0.03
	var b_out := _radius_of(b) > outer_radius + 0.03
	if not a_out and not b_out:
		return false
	var closest := _closest_on_segment(a, b, center)
	if _radius_of(closest) >= outer_radius - 0.03:
		return false
	return not _segment_near_gate(a, b)


func _segment_near_gate(a: Vector3, b: Vector3) -> bool:
	for gate: Vector3 in gates:
		if _segment_distance(a, b, gate) <= 0.45:
			return true
	return false


func _neighbors_of(index: int, start: int, goal: int, start_links: Array[int], goal_links: Array[int]) -> Array[int]:
	if index == start:
		return start_links
	if index == goal:
		return []
	var found: Array[int] = []
	for link: int in _links[index]:
		found.append(link)
	if goal_links.has(index):
		found.append(goal)
	return found


func _reconstruct(came: PackedInt32Array, start: int, goal: int, flat_from: Vector3, flat_to: Vector3, count: int) -> Array[Vector3]:
	var route: Array[Vector3] = []
	var cursor := goal
	var guard := 0
	while cursor != -1 and guard < count + 4:
		route.append(_at(cursor, flat_from, flat_to, count))
		if cursor == start:
			break
		cursor = came[cursor]
		guard += 1
	route.reverse()
	return route


func _at(index: int, flat_from: Vector3, flat_to: Vector3, count: int) -> Vector3:
	if index == count:
		return flat_from
	if index == count + 1:
		return flat_to
	return nodes[index]


func _radius_of(point: Vector3) -> float:
	return Vector2(point.x - center.x, point.z - center.z).length()


static func _join(raw: Array, a: int, b: int) -> void:
	if a == b:
		return
	var left: Array = raw[a]
	if not left.has(b):
		left.append(b)
	var right: Array = raw[b]
	if not right.has(a):
		right.append(b)


static func _near_any(angle: float, angles: PackedFloat32Array, tolerance: float) -> bool:
	for other: float in angles:
		if absf(angle_difference(angle, other)) <= tolerance:
			return true
	return false


static func _dir(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, cos(angle))


static func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


static func _first_block(a: Vector3, b: Vector3, blocks: Array) -> int:
	var segment := b - a
	var span2 := segment.length_squared()
	if span2 < 0.000001:
		return -1
	var best := -1
	var best_t := INF
	for index: int in blocks.size():
		var block: Dictionary = blocks[index]
		if not block.has("center"):
			continue
		var radius := float(block.get("radius", 0.0))
		if radius <= 0.0:
			continue
		var block_at := Vector3(block.center.x, 0.0, block.center.z)
		if _segment_distance(a, b, block_at) >= radius:
			continue
		var t := clampf((block_at - a).dot(segment) / span2, 0.0, 1.0)
		if best < 0 or t < best_t - 0.0001 or (absf(t - best_t) <= 0.0001 and index < best):
			best = index
			best_t = t
	return best


static func _detour(a: Vector3, b: Vector3, block_at: Vector3, radius: float, blocks: Array) -> Array[Vector3]:
	var dir := b - a
	var span := dir.length()
	if span < 0.001:
		return []
	dir /= span
	var left := Vector3(-dir.z, 0.0, dir.x)
	var best: Array[Vector3] = []
	var best_span := INF
	for side_sign: float in [1.0, -1.0]:
		var side := left * side_sign
		for extra: float in [0.08, 0.28, 0.6]:
			var margin := radius + extra
			var apex := block_at + side * margin
			var one: Array[Vector3] = [apex]
			if _route_clear(a, one, b, blocks) and _span(a, one, b) < best_span - 0.0001:
				best = one
				best_span = _span(a, one, b)
			var two: Array[Vector3] = [apex - dir * margin, apex + dir * margin]
			if _route_clear(a, two, b, blocks) and _span(a, two, b) < best_span - 0.0001:
				best = two
				best_span = _span(a, two, b)
	if not best.is_empty():
		return best
	var margin2 := radius + 0.8
	var apex2 := block_at + left * margin2
	return [apex2 - dir * margin2, apex2 + dir * margin2]


static func _route_clear(a: Vector3, middle: Array[Vector3], b: Vector3, blocks: Array) -> bool:
	var points: Array[Vector3] = [a]
	points.append_array(middle)
	points.append(b)
	for i: int in points.size() - 1:
		for block: Dictionary in blocks:
			if not block.has("center"):
				continue
			var radius := float(block.get("radius", 0.0))
			if radius <= 0.0:
				continue
			var block_at := Vector3(block.center.x, 0.0, block.center.z)
			if _segment_distance(points[i], points[i + 1], block_at) < radius:
				return false
	return true


static func _span(a: Vector3, middle: Array[Vector3], b: Vector3) -> float:
	var total := 0.0
	var prev := a
	for point: Vector3 in middle:
		total += prev.distance_to(point)
		prev = point
	return total + prev.distance_to(b)


static func _segment_distance(a: Vector3, b: Vector3, point: Vector3) -> float:
	return _closest_on_segment(a, b, point).distance_to(point)


static func _closest_on_segment(a: Vector3, b: Vector3, point: Vector3) -> Vector3:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0000001:
		return a
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return a + ab * t
