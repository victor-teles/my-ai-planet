class_name Steering
extends RefCounted
## Headless steering shared by villagers and, later, herds. No scene tree.
## Heading is radians with Settlement's convention, atan2(direction.x, direction.z), so 0 faces +Z.
## Y is ignored; motion stays on the XZ plane. Pure: no RNG, no clock, no nodes.

const SLOW_RADIUS := 1.2 ## world units over which arrive eases off
const STOP_RADIUS := 0.05
const TURN_IN_PLACE_ANGLE := TAU / 3.0 ## more than 120 degrees
const DEFAULT_COMFORT := 0.64
const FIRE_RADIUS := 0.4
const WALL_THICKNESS := 0.16
const BODY_RADIUS := 0.18


## A mover dictionary. speed is how fast it is moving now, along its heading.
static func mover(position: Vector3, heading: float, speed: float, radius: float, max_speed: float, max_acceleration: float, max_turn_rate: float, comfort: float = DEFAULT_COMFORT, id: int = -1) -> Dictionary:
	var forward := _forward(heading)
	var body := {
		"position": position,
		"velocity": forward * speed,
		"heading": heading,
		"radius": radius,
		"max_speed": max_speed,
		"max_acceleration": max_acceleration,
		"max_turn_rate": max_turn_rate,
		"comfort": comfort,
	}
	if id >= 0:
		body["id"] = id
	return body


## Acceleration toward target that eases to a stop inside slow_radius.
## Never larger than max acceleration, so a full stop takes more than one frame.
static func arrive(mover: Dictionary, target: Vector3, slow_radius: float = SLOW_RADIUS) -> Vector3:
	return _as_accel(mover, _arrive_velocity(mover, target, slow_radius))


## Acceleration away from neighbors closer than comfort.
## One uniform grid (cell = comfort) so a step does not allocate a pair list.
static func separate(mover: Dictionary, neighbors: Array, comfort: float = -1.0) -> Vector3:
	var space := comfort if comfort >= 0.0 else _comfort_of(mover)
	var push := _separate_velocity(mover, neighbors, space)
	if push.length_squared() < 0.000001:
		return Vector3.ZERO
	return _as_accel(mover, push)


## Acceleration that steers around discs (buildings, the fire, rocks) and wall capsules.
## Disc: {kind, center, radius}. Wall: {kind: "wall", a, b, radius}.
static func avoid(mover: Dictionary, obstacles: Array) -> Vector3:
	var dodge := _avoid_velocity(mover, obstacles)
	if dodge.length_squared() < 0.000001:
		return Vector3.ZERO
	return _as_accel(mover, dodge)


## One tick of arrive + separate + avoid. Returns the next mover plus turn_in_place.
static func step(mover: Dictionary, target: Vector3, neighbors: Array, obstacles: Array, delta: float) -> Dictionary:
	var comfort := _comfort_of(mover)
	var arrive_v := _arrive_velocity(mover, target, SLOW_RADIUS)
	var separate_v := _separate_velocity(mover, neighbors, comfort)
	var avoid_v := _avoid_velocity(mover, obstacles)
	var max_speed := float(mover.max_speed)
	var want := _blend(arrive_v, separate_v, avoid_v, max_speed)

	var heading := float(mover.heading)
	var face := want
	var to_target := _xz(target) - _xz(mover.position)
	if face.length_squared() < 0.0009 and to_target.length() > STOP_RADIUS:
		face = to_target
	var desired_heading := heading
	if face.length_squared() >= 0.0009:
		desired_heading = atan2(face.x, face.z)
	var diff := angle_difference(heading, desired_heading)
	# A wide turn is made in place. Walking it out would crab sideways at full speed.
	var turn_in_place := absf(diff) > TURN_IN_PLACE_ANGLE
	var max_turn := float(mover.max_turn_rate) * delta
	heading += clampf(diff, -max_turn, max_turn)

	var old_forward := _forward(float(mover.heading))
	var speed := maxf(_xz(mover.velocity).dot(old_forward), 0.0)
	var max_dv := float(mover.max_acceleration) * delta
	if turn_in_place:
		speed = move_toward(speed, 0.0, max_dv)
	else:
		var remain := absf(angle_difference(heading, desired_heading))
		var align := 1.0
		if remain > 0.5:
			align = clampf((TURN_IN_PLACE_ANGLE - remain) / (TURN_IN_PLACE_ANGLE - 0.5), 0.15, 1.0)
		var target_speed := minf(want.length(), max_speed) * align
		speed = clampf(move_toward(speed, target_speed, max_dv), 0.0, max_speed)
	var velocity := _forward(heading) * speed
	var pos := _xz(mover.position)
	velocity = _slide(pos, velocity, obstacles, float(mover.radius))
	pos += velocity * delta
	pos = _nudge(pos, mover, neighbors, delta)
	pos = _eject(pos, obstacles, float(mover.radius))
	pos.y = (mover.position as Vector3).y

	var next := mover.duplicate()
	next["position"] = pos
	next["velocity"] = velocity
	next["heading"] = wrapf(heading, -PI, PI)
	next["turn_in_place"] = turn_in_place
	return next


## Flocking for herds: a desired velocity toward the middle of the mates within radius, as
## strong as how far the mover has strayed past half that radius. Zero with no mates near.
static func cohesion(mover: Dictionary, mates: Array, radius: float) -> Vector3:
	var pos := _xz(mover.position)
	var sum := Vector3.ZERO
	var count := 0
	for other: Dictionary in mates:
		if _is_self(mover, other):
			continue
		var at := _xz(other.position)
		if at.distance_to(pos) <= radius:
			sum += at
			count += 1
	if count == 0:
		return Vector3.ZERO
	var offset := sum / float(count) - pos
	var reach := clampf((offset.length() - radius * 0.5) / maxf(radius * 0.5, 0.001), 0.0, 1.0)
	if reach <= 0.0:
		return Vector3.ZERO
	return offset.normalized() * float(mover.max_speed) * reach


## Flocking for herds: the mean velocity of the mates within radius, no faster than max speed.
static func alignment(mover: Dictionary, mates: Array, radius: float) -> Vector3:
	var pos := _xz(mover.position)
	var sum := Vector3.ZERO
	var count := 0
	for other: Dictionary in mates:
		if _is_self(mover, other):
			continue
		if _xz(other.position).distance_to(pos) <= radius:
			sum += _xz(other.velocity)
			count += 1
	if count == 0:
		return Vector3.ZERO
	return _clamp_len(sum / float(count), float(mover.max_speed))


## The point to hand step() so a herd animal heads for target while keeping with its mates:
## cohesion and alignment bend the way there, and step() keeps the separation and avoidance.
static func flock_target(mover: Dictionary, target: Vector3, mates: Array, radius: float, cohesion_weight: float = 0.5, alignment_weight: float = 0.4, lookahead: float = 0.8) -> Vector3:
	var bend := cohesion(mover, mates, radius) * cohesion_weight + alignment(mover, mates, radius) * alignment_weight
	if bend.length_squared() < 0.000001:
		return target
	var aim := _xz(target) + bend * lookahead
	aim.y = target.y
	return aim


## Disc radius that covers a later-age footprint. SIZES packs (half-width, half-depth, height)
## with the depth in Y, because the art const is a Vector3.
static func footprint_radius(type: String) -> float:
	if not BuildingArt.SIZES.has(type):
		return 0.45
	var size: Vector3 = BuildingArt.SIZES[type]
	return Vector2(size.x, size.y).length()


static func building_obstacle(type: String, center: Vector3) -> Dictionary:
	return disc_obstacle(center, footprint_radius(type), "building")


static func fire_obstacle(center: Vector3, radius: float = FIRE_RADIUS) -> Dictionary:
	return disc_obstacle(center, radius, "fire")


static func wall_obstacle(a: Vector3, b: Vector3, radius: float = WALL_THICKNESS) -> Dictionary:
	return {"kind": "wall", "a": _xz(a), "b": _xz(b), "radius": radius}


static func disc_obstacle(center: Vector3, radius: float, kind: String = "disc") -> Dictionary:
	return {"kind": kind, "center": _xz(center), "radius": radius}


static func _arrive_velocity(mover: Dictionary, target: Vector3, slow_radius: float) -> Vector3:
	var offset := _xz(target) - _xz(mover.position)
	var distance := offset.length()
	if distance <= STOP_RADIUS:
		return Vector3.ZERO
	var max_speed := float(mover.max_speed)
	var max_accel := maxf(float(mover.max_acceleration), 0.01)
	var speed := max_speed
	if distance < slow_radius:
		speed = max_speed * distance / slow_radius
	# Don't ask for a speed that max acceleration cannot shed before the point.
	var brake := sqrt(2.0 * max_accel * maxf(distance - STOP_RADIUS, 0.0))
	speed = minf(speed, brake)
	return offset * (speed / distance)


static func _separate_velocity(mover: Dictionary, neighbors: Array, comfort: float) -> Vector3:
	if neighbors.is_empty() or comfort <= 0.0:
		return Vector3.ZERO
	var cell := maxf(comfort, 0.05)
	var grid := _hash_neighbors(neighbors, cell)
	var pos := _xz(mover.position)
	var origin := _cell_of(pos, cell)
	var push := Vector3.ZERO
	var max_speed := float(mover.max_speed)
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var key := Vector2i(origin.x + dx, origin.y + dz)
			if not grid.has(key):
				continue
			var bucket: Array = grid[key]
			for index: int in bucket:
				var other: Dictionary = neighbors[index]
				if _is_self(mover, other):
					continue
				var away := pos - _xz(other.position)
				var dist := away.length()
				if dist >= comfort:
					continue
				if dist <= 0.0001:
					var spin := float(int(other.get("id", 1)) - int(mover.get("id", 0)))
					away = Vector3(sin(spin), 0.0, cos(spin))
					dist = 0.0001
				else:
					away /= dist
				var weight := (comfort - dist) / comfort
				var radii := float(mover.get("radius", BODY_RADIUS)) + float(other.get("radius", BODY_RADIUS))
				# Full push before the bodies meet, so arrive cannot pack them through each other.
				if dist < radii + 0.05 or dist < comfort * 0.7:
					weight = maxf(weight, 1.0)
				push += away * weight
	if push.length_squared() < 0.000001:
		return Vector3.ZERO
	var urgency := clampf(push.length(), 0.0, 1.0)
	return push.normalized() * max_speed * urgency


## Cell size is the comfort distance, so anyone inside comfort sits in this cell or a neighbor.
static func _hash_neighbors(neighbors: Array, cell: float) -> Dictionary:
	var grid := {}
	for index: int in neighbors.size():
		var other: Dictionary = neighbors[index]
		var key := _cell_of(_xz(other.position), cell)
		var bucket: Array
		if grid.has(key):
			bucket = grid[key]
		else:
			bucket = []
			grid[key] = bucket
		bucket.append(index)
	return grid


static func _avoid_velocity(mover: Dictionary, obstacles: Array) -> Vector3:
	if obstacles.is_empty():
		return Vector3.ZERO
	var pos := _xz(mover.position)
	var radius := float(mover.get("radius", BODY_RADIUS))
	var max_speed := float(mover.max_speed)
	var heading := float(mover.get("heading", 0.0))
	var forward := _forward(heading)
	var vel := _xz(mover.velocity)
	var steer := Vector3.ZERO
	for obstacle: Dictionary in obstacles:
		var closest := _obstacle_closest(obstacle, pos)
		var limit := float(obstacle.get("radius", 0.2)) + radius
		var away := pos - closest
		var dist := away.length()
		if dist <= 0.0001:
			away = Vector3(1.0, 0.0, 0.0)
			dist = 0.0001
		else:
			away /= dist
		if dist < limit:
			steer += away * max_speed * (1.0 + (limit - dist) / limit)
			continue
		var probe := pos + forward * minf(maxf(vel.length(), max_speed * 0.45) * 0.85 + radius, 1.15)
		if vel.length_squared() > 0.0004:
			probe = pos + vel.normalized() * minf(vel.length() * 0.8 + radius, 1.15)
		var ahead := _obstacle_closest(obstacle, probe)
		var ahead_dist := probe.distance_to(ahead)
		if ahead_dist >= limit + 0.1:
			continue
		var side := Vector3(-forward.z, 0.0, forward.x)
		if side.length_squared() < 0.0001:
			side = Vector3(1.0, 0.0, 0.0)
		elif side.dot(away) < 0.0:
			side = -side
		var strength := clampf((limit + 0.1 - ahead_dist) / limit, 0.0, 1.0)
		steer += (side.normalized() * 0.85 + away * 0.45) * max_speed * strength
	return _clamp_len(steer, max_speed)


static func _blend(arrive_v: Vector3, separate_v: Vector3, avoid_v: Vector3, max_speed: float) -> Vector3:
	var want := arrive_v
	if separate_v.length_squared() > 0.000001:
		var urgency := clampf(separate_v.length() / maxf(max_speed, 0.01), 0.0, 1.0)
		want = _clamp_len(separate_v + arrive_v * (1.0 - urgency), max_speed)
	if avoid_v.length_squared() > 0.000001:
		var dodge := clampf(avoid_v.length() / maxf(max_speed, 0.01), 0.0, 1.0)
		want = _clamp_len(avoid_v + want * (1.0 - dodge), max_speed)
	return _clamp_len(want, max_speed)


static func _slide(pos: Vector3, velocity: Vector3, obstacles: Array, radius: float) -> Vector3:
	var slid := velocity
	for obstacle: Dictionary in obstacles:
		var closest := _obstacle_closest(obstacle, pos)
		var limit := float(obstacle.get("radius", 0.2)) + radius
		var away := pos - closest
		var dist := away.length()
		if dist <= 0.0001 or dist > limit + 0.05:
			continue
		away /= dist
		var into := slid.dot(away)
		if into < 0.0:
			slid -= away * into
	return slid


static func _eject(pos: Vector3, obstacles: Array, radius: float) -> Vector3:
	var result := pos
	for _pass: int in 3:
		for obstacle: Dictionary in obstacles:
			var closest := _obstacle_closest(obstacle, result)
			var limit := float(obstacle.get("radius", 0.2)) + radius
			var away := result - closest
			var dist := away.length()
			if dist >= limit:
				continue
			if dist <= 0.0001:
				away = Vector3(0.0, 0.0, 1.0)
				dist = 0.0001
			else:
				away /= dist
			# Only the penetration comes back out, and a mover who started outside barely entered.
			result += away * (limit - dist + 0.001)
	return result


static func _nudge(pos: Vector3, mover: Dictionary, neighbors: Array, delta: float) -> Vector3:
	if neighbors.is_empty():
		return pos
	var radius := float(mover.get("radius", BODY_RADIUS))
	# Same grid rule as separate: the cell is at least the distance we care about, so 3x3 is enough.
	var cell := maxf(_comfort_of(mover), radius * 4.0)
	var grid := _hash_neighbors(neighbors, cell)
	var origin := _cell_of(pos, cell)
	var budget := float(mover.max_speed) * delta
	var result := pos
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var key := Vector2i(origin.x + dx, origin.y + dz)
			if not grid.has(key):
				continue
			var bucket: Array = grid[key]
			for index: int in bucket:
				var other: Dictionary = neighbors[index]
				if _is_self(mover, other):
					continue
				var away := result - _xz(other.position)
				var dist := away.length()
				var limit := radius + float(other.get("radius", radius))
				if dist >= limit:
					continue
				if dist <= 0.0001:
					var spin := float(int(mover.get("id", 0)))
					away = Vector3(sin(spin + 1.0), 0.0, cos(spin + 1.0))
					dist = 0.0001
				else:
					away /= dist
				var fix := minf(limit - dist, budget)
				result += away * fix
				budget -= fix
				if budget <= 0.0:
					return result
	return result


static func _obstacle_closest(obstacle: Dictionary, point: Vector3) -> Vector3:
	var kind := String(obstacle.get("kind", "disc"))
	if (kind == "wall" or kind == "capsule") and obstacle.has("a") and obstacle.has("b"):
		return _closest_on_segment(_xz(obstacle.a), _xz(obstacle.b), point)
	if obstacle.has("center"):
		return _xz(obstacle.center)
	return point


static func _closest_on_segment(a: Vector3, b: Vector3, point: Vector3) -> Vector3:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0000001:
		return a
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return a + ab * t


static func _as_accel(mover: Dictionary, desired: Vector3) -> Vector3:
	return _clamp_len(desired - _xz(mover.velocity), float(mover.max_acceleration))


static func _comfort_of(mover: Dictionary) -> float:
	if mover.has("comfort"):
		return float(mover.comfort)
	return DEFAULT_COMFORT


static func _is_self(mover: Dictionary, other: Dictionary) -> bool:
	return mover.has("id") and other.has("id") and mover.id == other.id


static func _cell_of(point: Vector3, cell: float) -> Vector2i:
	return Vector2i(floori(point.x / cell), floori(point.z / cell))


static func _forward(heading: float) -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))


static func _xz(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


static func _clamp_len(v: Vector3, limit: float) -> Vector3:
	var length := v.length()
	if length > limit and length > 0.000001:
		return v * (limit / length)
	return v
