class_name IslandMesh
extends RefCounted
## Builds the floating island as one smooth mesh: a grassy top, a dirt lip, and a rocky
## underside tapering to a point. Colors are painted per vertex; the toon shader does the rest.

const SEGMENTS := 96
const TOP_RINGS := 26
const UNDER_RINGS := 16
const LIP_DROP := 1.3
const DEPTH := 10.0

const GRASS := Color(0.34, 0.70, 0.36)
const GRASS_LIGHT := Color(0.56, 0.82, 0.40)
const SAND := Color(0.90, 0.80, 0.58)
const DIRT := Color(0.52, 0.32, 0.24)
const DIRT_LIGHT := Color(0.72, 0.50, 0.34)
const ROCK := Color(0.52, 0.36, 0.46)
const ROCK_DEEP := Color(0.30, 0.20, 0.36)


static func build(shape: IslandShape, seed_value: int) -> ArrayMesh:
	var jitter := FastNoiseLite.new()
	jitter.seed = seed_value + 7
	jitter.frequency = 0.35
	var tint := FastNoiseLite.new()
	tint.seed = seed_value + 9
	tint.frequency = 0.25

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var positions := PackedVector3Array()

	# Top center.
	var center := shape.surface_point(0.0, 0.0)
	st.set_color(GRASS)
	st.add_vertex(center)
	positions.append(center)

	var rows: Array[PackedInt32Array] = []
	var edge_heights := PackedFloat32Array()
	edge_heights.resize(SEGMENTS)

	# Grassy top, ring by ring.
	for ring: int in range(1, TOP_RINGS + 1):
		var t := float(ring) / TOP_RINGS
		var row := PackedInt32Array()
		for s: int in SEGMENTS:
			var angle := TAU * s / SEGMENTS
			var radius := shape.edge_radius(angle) * pow(t, 0.85)
			var point := shape.surface_point(cos(angle) * radius, sin(angle) * radius)
			var color := GRASS.lerp(GRASS_LIGHT, clampf(tint.get_noise_2d(point.x, point.z) * 0.8 + 0.4, 0.0, 1.0))
			if point.y < IslandShape.WATER_LEVEL + 0.2 and Vector2(point.x, point.z).distance_to(IslandShape.POND_CENTER) < IslandShape.POND_RADIUS * 1.4:
				color = SAND
			if ring == TOP_RINGS:
				edge_heights[s] = point.y
			st.set_color(color)
			st.add_vertex(point)
			row.append(positions.size())
			positions.append(point)
		rows.append(row)

	# Grass overhang, a layered dirt cliff, then the rocky underside tapering down.
	var cliff_rings: Array[Dictionary] = [
		{"drop": 0.12, "bulge": 1.015, "color": GRASS},
		{"drop": 0.45, "bulge": 1.0, "color": DIRT_LIGHT},
		{"drop": 0.85, "bulge": 0.99, "color": DIRT},
		{"drop": LIP_DROP, "bulge": 0.97, "color": DIRT_LIGHT.lerp(ROCK, 0.5)},
	]
	for ring: Dictionary in cliff_rings:
		var row := PackedInt32Array()
		for s: int in SEGMENTS:
			var angle := TAU * s / SEGMENTS
			var radius := shape.edge_radius(angle) * float(ring["bulge"])
			var point := Vector3(cos(angle) * radius, edge_heights[s] - float(ring["drop"]), sin(angle) * radius)
			st.set_color(ring["color"])
			st.add_vertex(point)
			row.append(positions.size())
			positions.append(point)
		rows.append(row)
	for ring: int in range(1, UNDER_RINGS + 1):
		var t := float(ring) / (UNDER_RINGS + 1)
		var row := PackedInt32Array()
		for s: int in SEGMENTS:
			var angle := TAU * s / SEGMENTS
			var bulge := 0.97 * (1.0 - pow(t, 0.75)) * (1.0 + 0.16 * jitter.get_noise_2d(s * 0.6, ring * 1.3))
			var radius := shape.edge_radius(angle) * bulge
			var y := -LIP_DROP - DEPTH * pow(t, 1.25) + 0.5 * jitter.get_noise_2d(s * 1.7, ring * 2.1)
			var color := ROCK.lerp(ROCK_DEEP, clampf(t * 1.4 - 0.2, 0.0, 1.0))
			var point := Vector3(cos(angle) * radius, y, sin(angle) * radius)
			st.set_color(color)
			st.add_vertex(point)
			row.append(positions.size())
			positions.append(point)
		rows.append(row)

	# Bottom tip.
	st.set_color(ROCK_DEEP)
	var tip := positions.size()
	positions.append(Vector3(0.0, -LIP_DROP - DEPTH - 1.2, 0.0))
	st.add_vertex(positions[tip])

	for s: int in SEGMENTS:
		var next := (s + 1) % SEGMENTS
		_triangle(st, positions, 0, rows[0][s], rows[0][next], Vector3.UP)
		_triangle(st, positions, rows[-1][s], rows[-1][next], tip, Vector3.DOWN)
	for r: int in rows.size() - 1:
		var outward_hint := Vector3.UP if r < TOP_RINGS - 1 else Vector3.ZERO
		for s: int in SEGMENTS:
			var next := (s + 1) % SEGMENTS
			_quad(st, positions, rows[r][s], rows[r][next], rows[r + 1][s], rows[r + 1][next], outward_hint)

	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, positions: PackedVector3Array, a: int, b: int, c: int, d: int, outward: Vector3) -> void:
	_triangle(st, positions, a, b, c, outward)
	_triangle(st, positions, b, d, c, outward)


## Adds a triangle facing `outward` (or away from the island's axis when outward is zero).
## Godot treats clockwise triangles as front-facing, whose normal is (c - a).cross(b - a).
static func _triangle(st: SurfaceTool, positions: PackedVector3Array, a: int, b: int, c: int, outward: Vector3) -> void:
	var pa := positions[a]
	var pb := positions[b]
	var pc := positions[c]
	var facing := outward
	if facing == Vector3.ZERO:
		var centroid := (pa + pb + pc) / 3.0
		facing = Vector3(centroid.x, 0.0, centroid.z).normalized() + Vector3.DOWN * 0.3
	if (pc - pa).cross(pb - pa).dot(facing) >= 0.0:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)
	else:
		st.add_index(a)
		st.add_index(c)
		st.add_index(b)
