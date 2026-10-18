extends TestCase
## Headless steering, gait and camp lanes. No scene tree.


## A walker at 0.42 reaches a point 4 units away and eases to a stop, with no jumped frame.
func test_arrive() -> void:
	var target := Vector3(0.0, 0.0, 4.0)
	var max_speed := 0.42
	var max_accel := 0.8
	var dt := 1.0 / 60.0
	var mover := Steering.mover(Vector3.ZERO, 0.0, max_speed, 0.18, max_speed, max_accel, 2.5)
	var max_step := 0.0
	var max_drop := 0.0
	var prev_speed := max_speed
	for _frame: int in 1200:
		var next: Dictionary = Steering.step(mover, target, [], [], dt)
		var moved := (next.position as Vector3).distance_to(mover.position)
		var speed := (next.velocity as Vector3).length()
		max_step = maxf(max_step, moved)
		max_drop = maxf(max_drop, prev_speed - speed)
		prev_speed = speed
		mover = next
		if (mover.position as Vector3).distance_to(target) < 0.12 and speed < 0.04:
			break
	var end := mover.position as Vector3
	var end_speed := (mover.velocity as Vector3).length()
	assert_true(end.distance_to(target) < 0.15, "ended %.3f from the point" % end.distance_to(target))
	assert_true(end_speed < 0.05, "ended still moving at %.3f" % end_speed)
	assert_true(max_step <= max_speed * dt + 0.0001, "a frame jumped %.4f" % max_step)
	assert_true(max_drop <= max_accel * dt + 0.0001, "speed fell %.4f in one frame" % max_drop)


## A target straight behind sets turn_in_place, and the body barely moves while it spins.
func test_turn_in_place() -> void:
	var target := Vector3(0.0, 0.0, -4.0)
	var start := Vector3(0.0, 0.0, 0.0)
	var dt := 1.0 / 60.0
	var mover := Steering.mover(start, 0.0, 0.42, 0.18, 0.42, 1.2, 2.2)
	var saw := false
	var drifted := 0.0
	for _frame: int in 240:
		var next: Dictionary = Steering.step(mover, target, [], [], dt)
		var vel := next.velocity as Vector3
		var forward := Vector3(sin(float(next.heading)), 0.0, cos(float(next.heading)))
		var sideways := (vel - forward * vel.dot(forward)).length()
		assert_true(sideways < 0.02, "slid sideways at %.3f" % sideways)
		if bool(next.turn_in_place):
			saw = true
			drifted = maxf(drifted, (next.position as Vector3).distance_to(start))
			mover = next
			continue
		mover = next
		break
	assert_true(saw, "a 180 degree target never turned in place")
	assert_true(drifted < 0.2, "moved %.3f while turning in place" % drifted)
	assert_true(absf(angle_difference(0.0, float(mover.heading))) > deg_to_rad(50.0), "heading did not catch up")


## 40 walkers in a 6x6 box, all heading for the middle. An overlap may happen, not linger.
func test_crowd_separation() -> void:
	var count := 40
	var cols := 8
	var rows := 5
	var radius := 0.16
	var comfort := 0.9
	var dt := 0.05
	var slack := 0.04
	var movers: Array[Dictionary] = []
	for i: int in count:
		var col := i % cols
		var row := int(i / cols)
		var pos := Vector3(-3.0 + (float(col) + 0.5) * (6.0 / float(cols)), 0.0, -3.0 + (float(row) + 0.5) * (6.0 / float(rows)))
		var heading := atan2(-pos.x, -pos.z)
		movers.append(Steering.mover(pos, heading, 0.42, radius, 0.42, 2.0, 5.0, comfort, i))
	var limit := radius * 2.0
	var streak := {}
	var max_streak := 0.0
	var peak := 0
	var worst := ""
	for _frame: int in int(8.0 / dt):
		var seen := {}
		var overlaps := 0
		for i: int in count:
			movers[i] = Steering.step(movers[i], Vector3.ZERO, movers, [], dt)
		for i: int in count:
			for j: int in range(i + 1, count):
				var dist := (movers[i].position as Vector3).distance_to(movers[j].position)
				if dist + slack < limit:
					overlaps += 1
					var key := "%d:%d" % [i, j]
					seen[key] = true
					streak[key] = float(streak.get(key, 0.0)) + dt
					if float(streak[key]) > max_streak:
						max_streak = float(streak[key])
						worst = "%s dist %.3f" % [key, dist]
		peak = maxi(peak, overlaps)
		var drop: Array[String] = []
		for key: String in streak.keys():
			if not seen.has(key):
				drop.append(key)
		for key: String in drop:
			streak.erase(key)
	assert_true(max_streak <= 0.4, "a pair overlapped for %.2fs (%s), peak count %d" % [max_streak, worst, peak])


## Walkers aimed at a point inside a building disc finish outside it.
func test_building_footprints() -> void:
	var at := Vector3(1.6, 0.0, 0.0)
	var house := Steering.building_obstacle("stone_house", at)
	var disc := float(house.radius)
	var size: Vector3 = BuildingArt.SIZES["stone_house"]
	assert_true(is_equal_approx(disc, Vector2(size.x, size.y).length()), "footprint disc")
	var starts: Array[Vector3] = [Vector3(1.6, 0.0, -2.2), Vector3(-0.6, 0.0, 0.0), Vector3(1.6, 0.0, 2.2)]
	var dt := 1.0 / 30.0
	for start: Vector3 in starts:
		assert_true(start.distance_to(at) > disc, "fixture starts inside the house")
		var heading := atan2(at.x - start.x, at.z - start.z)
		var mover := Steering.mover(start, heading, 0.42, 0.18, 0.42, 1.4, 3.2)
		for _frame: int in 360:
			mover = Steering.step(mover, at, [], [house], dt)
			var dist := (mover.position as Vector3).distance_to(at)
			assert_true(dist + 0.02 >= disc + 0.18, "entered the house, clearance %.3f" % (dist - disc))
		var end_dist := (mover.position as Vector3).distance_to(at)
		assert_true(end_dist > disc, "ended inside the footprint, dist %.3f disc %.3f" % [end_dist, disc])


## The fire is a disc and a wall segment is a capsule: neither can be walked through.
func test_fire_and_wall() -> void:
	var dt := 1.0 / 30.0
	var fire := Steering.fire_obstacle(Vector3(0.0, 0.0, 2.0), 0.45)
	var mover := Steering.mover(Vector3.ZERO, 0.0, 0.42, 0.18, 0.42, 1.2, 3.0)
	for _frame: int in 240:
		mover = Steering.step(mover, Vector3(0.0, 0.0, 4.0), [], [fire], dt)
		var dist := Vector2(mover.position.x, mover.position.z - 2.0).length()
		assert_true(dist + 0.02 >= 0.45 + 0.18, "walked into the fire")
	var wall := Steering.wall_obstacle(Vector3(-3.0, 0.0, 2.0), Vector3(3.0, 0.0, 2.0), 0.2)
	mover = Steering.mover(Vector3(0.0, 0.0, 0.0), 0.0, 0.42, 0.18, 0.42, 1.2, 3.0)
	for _frame: int in 180:
		mover = Steering.step(mover, Vector3(0.0, 0.0, 4.0), [], [wall], dt)
		var gap := _segment_distance(Vector3(-3.0, 0.0, 2.0), Vector3(3.0, 0.0, 2.0), mover.position)
		assert_true(gap + 0.02 >= 0.2 + 0.18, "crossed the wall")


## Inside the camp to outside the wall goes through a gate, not straight across.
func test_gate_path() -> void:
	var camp := Vector3(10.0, 0.0, -4.0)
	var inner := 1.3
	var wall := 2.68
	var lanes := Lanes.build(camp, [inner, wall], [0.0, PI * 0.5, PI, PI * 1.5], [0.0, PI])
	assert_true(lanes.nodes.size() >= 20 and lanes.nodes.size() <= 40, "graph has %d nodes" % lanes.nodes.size())
	assert_true(not lanes.gates.is_empty(), "no gates")
	var start := camp + Vector3(0.2, 0.0, 0.25)
	var goal := camp + Vector3(0.1, 0.0, wall + 3.0)
	assert_true(start.distance_to(camp) < wall and goal.distance_to(camp) > wall, "fixture is not inside-to-outside")
	var route := lanes.path(start, goal)
	var saw_gate := false
	for point: Vector3 in route:
		for gate: Vector3 in lanes.gates:
			if point.distance_to(gate) <= 0.001:
				saw_gate = true
	assert_true(saw_gate, "path never touched a gate: %s" % [route])
	for i: int in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var ra := a.distance_to(camp)
		var rb := b.distance_to(camp)
		if (ra - wall) * (rb - wall) >= 0.0:
			continue
		var near := false
		for gate: Vector3 in lanes.gates:
			if _segment_distance(a, b, gate) <= 0.45:
				near = true
		assert_true(near, "segment cuts the wall away from a gate")


## A blocked disc in the wild adds 1 or 2 waypoints, and the same blocks always detour the same way.
func test_wander_avoids_blocks() -> void:
	var start := Vector3(0.0, 0.0, 0.0)
	var goal := Vector3(4.0, 0.0, 0.0)
	var clear := Lanes.wander_waypoints(start, goal, [])
	assert_eq(clear.size(), 2, "a clear walk")
	var rock := {"center": Vector3(2.0, 0.0, 0.0), "radius": 0.55}
	var route := Lanes.wander_waypoints(start, goal, [rock])
	var again := Lanes.wander_waypoints(start, goal, [rock])
	assert_true(route.size() == 3 or route.size() == 4, "added %d points" % (route.size() - 2))
	assert_eq(route.size(), again.size(), "drift between calls")
	for i: int in route.size():
		assert_true((route[i] as Vector3).distance_to(again[i]) < 0.0001, "waypoint %d moved" % i)
	for i: int in route.size() - 1:
		var gap := _segment_distance(route[i], route[i + 1], rock.center)
		assert_true(gap >= float(rock.radius) - 0.0001, "still clips the rock, gap %.3f" % gap)


## Sick elders are slower than healthy children, stone is slower than empty hands, drift is seeded.
func test_gait() -> void:
	var adult := Gait.profile(30, 0.5, 0.5, 100.0, false, 55.0, PackedStringArray(), "")
	assert_true(absf(float(adult.speed) - 0.42) < 0.02, "average adult walks at %.3f" % adult.speed)
	var child := Gait.profile(8, 0.5, 0.4, 100.0, false, 60.0, PackedStringArray(), "")
	var elder := Gait.profile(72, 0.5, 0.5, 45.0, true, 30.0, PackedStringArray(), "")
	assert_true(float(elder.speed) < float(child.speed), "sick elder %.3f vs child %.3f" % [elder.speed, child.speed])
	assert_true(float(child.speed) > float(adult.speed), "children should be faster")
	assert_true(float(elder.stoop) > float(adult.stoop), "elders stoop")
	assert_true(float(elder.limp) > 0.5, "the sick limp")
	assert_true(bool(elder.head_down), "low mood looks down")
	assert_true(float(child.bounce) > 0.4, "children bounce")
	var empty := Gait.profile(30, 0.5, 0.5, 100.0, false, 55.0, PackedStringArray(), "")
	var food := Gait.profile(30, 0.5, 0.5, 100.0, false, 55.0, PackedStringArray(), "food")
	var wood := Gait.profile(30, 0.5, 0.5, 100.0, false, 55.0, PackedStringArray(), "wood")
	var stone := Gait.profile(30, 0.5, 0.5, 100.0, false, 55.0, PackedStringArray(), "stone")
	assert_true(float(stone.speed) < float(empty.speed), "stone %.3f vs empty %.3f" % [stone.speed, empty.speed])
	assert_true(float(food.speed) < float(empty.speed) and float(wood.speed) < float(food.speed) and float(stone.speed) < float(wood.speed), "load order")
	var proud := Gait.profile(72, 0.5, 0.5, 80.0, false, 50.0, PackedStringArray(["proud"]), "")
	var plain_elder := Gait.profile(72, 0.5, 0.5, 80.0, false, 50.0, PackedStringArray(), "")
	assert_true(float(proud.stoop) < float(plain_elder.stoop), "proud stands up")
	var shy := Gait.profile(30, 0.5, 0.5, 100.0, false, 60.0, PackedStringArray(["shy"]), "")
	var plain := Gait.profile(30, 0.5, 0.5, 100.0, false, 60.0, PackedStringArray(), "")
	assert_true(float(shy.comfort) > float(plain.comfort), "shy keeps more distance")
	var fierce := Gait.profile(30, 0.5, 0.5, 100.0, false, 55.0, PackedStringArray(["fierce"]), "")
	assert_true(float(fierce.speed) > float(plain.speed), "fierce is a bit faster")
	var happy := Gait.profile(30, 0.5, 0.5, 100.0, false, 90.0, PackedStringArray(), "")
	assert_true(float(happy.bounce) > 0.4, "high mood bounces")
	var one := Gait.drift(1)
	var two := Gait.drift(2)
	var again := Gait.drift(1)
	assert_ne(one, two, "seeds 1 and 2")
	assert_eq(one, again, "same seed")
	assert_true(absf(float(one.speed)) < 0.05 and absf(float(one.pause)) < 0.05, "drift is small")


func _segment_distance(a: Vector3, b: Vector3, point: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0000001:
		return a.distance_to(point)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return (a + ab * t).distance_to(point)
