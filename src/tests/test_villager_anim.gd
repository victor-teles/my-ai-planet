extends TestCase
## The villager animation set (VillagerClips), its API in VillagerArt and the animator's level of
## detail. Figures are built off the scene tree and stepped by hand, so no camera is needed.

const DT := 1.0 / 60.0
const ACTIVITIES: Array[String] = ["infant", "playing", "sick", "resting", "mourning", "teaching", "working", "idle", "nursing", "courting"]


## Every trade, meeting and rest Settlement can show has a baked clip with tracks.
func test_every_activity_maps_to_a_clip() -> void:
	var library := VillagerClips.library()
	var wanted: Array[String] = ["", "die", "lie", "sit"]
	var jobs: Array = Settlement.TOOLS.keys() + ["potter", "weaver", "shaman", "nobody"]
	for job: String in jobs:
		wanted.append(VillagerArt.work_action(job))
	for kind: String in Settlement.EMOTES.keys() + ["unknown"]:
		wanted.append(VillagerArt.meet_action(kind))
	for activity: String in ACTIVITIES:
		wanted.append(VillagerArt.rest_action(activity))
	for action: String in wanted:
		if action.is_empty():
			continue
		assert_true(VillagerClips.has_action(action), "no action %s" % action)
		assert_true(library.has_animation(action), "no clip for %s" % action)
	for action: String in VillagerClips.actions():
		var clip := library.get_animation(action)
		assert_true(clip != null and clip.get_track_count() > 20, "%s has %d tracks" % [action, clip.get_track_count() if clip else 0])
	for gait: String in VillagerClips.GAIT_NAMES + VillagerClips.IDLES.keys() + ["carry"]:
		assert_true(library.has_animation(gait), "no clip for %s" % gait)
	for gesture: String in VillagerClips.GESTURES:
		assert_true(library.has_animation("once_" + gesture), "no clip for gesture %s" % gesture)
	# The walk is a one-second cycle and the gaits get longer strides as they speed up from the walk.
	var lengths := VillagerClips.cycle_lengths()
	assert_eq(library.get_animation("walk").length, 1.0, "walk cycle length")
	assert_true(lengths[0] > 0.0 and lengths[1] > lengths[0] and lengths[2] > lengths[0], "cycle lengths %s" % lengths)


## Near the camera every frame, further out every 2nd and 3rd, off screen every 4th.
func test_lod_rate_by_distance() -> void:
	assert_eq(VillagerAnimator.rate_for(5.0, true), 1, "near")
	assert_eq(VillagerAnimator.rate_for(VillagerAnimator.NEAR + 1.0, true), 2, "middle")
	assert_eq(VillagerAnimator.rate_for(VillagerAnimator.MID + 5.0, true), 3, "far")
	assert_eq(VillagerAnimator.rate_for(5.0, false), 4, "off screen, even if close")
	assert_eq(VillagerAnimator.rate_for(100.0, false), 4, "off screen and far")


## Forty off-screen villagers made on one frame update on four frames, ten at a time, and the
## time between updates adds up to the time that passed.
func test_lod_updates_are_staggered() -> void:
	var animators: Array[VillagerAnimator] = []
	var figures: Array[Node3D] = []
	for i: int in 40:
		var figure := VillagerArt.make(VillagerArt.appearance(i, i % 2 == 0, 30, false, Color.WHITE), 1000 + i)
		var animator := VillagerArt.animator(figure)
		animator.fixed_rate = VillagerAnimator.RATE_HIDDEN
		animator.measure = false
		figures.append(figure)
		animators.append(animator)
	var times: Array[float] = []
	for animator: VillagerAnimator in animators:
		times.append(0.0)
	var most := 0
	for frame: int in 16:
		var updated := 0
		for i: int in animators.size():
			var animator := animators[i]
			var due := animator.updates_this_frame()
			var before := animator._pending
			animator._process(DT)
			if animator._pending == 0.0:
				updated += 1
				times[i] += before + DT
				assert_true(due, "updates_this_frame said no but it updated")
		most = maxi(most, updated)
	assert_eq(most, 10, "most updates on one frame")
	for i: int in times.size():
		var pending := animators[i]._pending
		assert_true(absf(times[i] + pending - 16.0 * DT) < 0.0001, "time lost: %.4f + %.4f" % [times[i], pending])
	for figure: Node3D in figures:
		figure.free()


## Walking, jogging and running at the speeds Settlement uses, the planted foot barely moves over
## the ground: the clip rate follows the distance moved.
func test_feet_do_not_slide() -> void:
	var adult := VillagerArt.appearance(3, false, 30, false, Color.WHITE)
	var child := VillagerArt.child_appearance(5, Color.WHITE)
	# The tree only poses a skeleton in a running scene, and the runner starts before the first frame.
	await (Engine.get_main_loop() as SceneTree).process_frame
	for case: Array in [[adult, 0.42, 0.12], [adult, 0.3, 0.12], [adult, 0.6, 0.12], [adult, 0.9, 0.12], [adult, 1.6, 0.12], [child, 1.1, 0.12]]:
		var slide := _slide(case[0], float(case[1]))
		print("        %s at %.2f: the planted foot drifts %.0f%% of the body's travel" % ["child" if (case[0] as Dictionary)["child"] else "adult", float(case[1]), slide * 100.0])
		assert_true(slide < float(case[2]), "planted foot slides %.2f of the body's speed at %.2f" % [slide, float(case[1])])


## An action gives way to walking while the figure moves, and comes back when it stops.
func test_actions_yield_to_walking() -> void:
	var figure := VillagerArt.make(VillagerArt.appearance(9, true, 30, false, Color.WHITE), 9)
	var animator := VillagerArt.animator(figure)
	animator.measure = false
	VillagerArt.play_action(figure, "sit")
	for i: int in 30:
		animator.update(DT)
	assert_eq(animator.state(), "sit", "standing still")
	VillagerArt.set_locomotion_speed(figure, 0.42)
	for i: int in 30:
		animator.update(DT)
	assert_eq(animator.state(), "move", "moving")
	VillagerArt.set_locomotion_speed(figure, 0.0)
	for i: int in 60:
		animator.update(DT)
	assert_eq(animator.state(), "sit", "stopped again")
	VillagerArt.play_action(figure, "mourn")
	var pose := figure.get_meta("pose") as VillagerPose
	assert_true(float(pose.extra.get("Neck", 0.0)) > 0.1, "a mourner bows the head")
	VillagerArt.play_action(figure, "")
	assert_eq(float(pose.extra.get("Neck", 0.0)), 0.0, "the bow goes with the action")
	figure.free()


## The shared neighbor grid gives the same separation as hashing per mover.
func test_shared_grid_matches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var crowd: Array = []
	for i: int in 60:
		var at := Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
		crowd.append(Steering.mover(at, rng.randf() * TAU, 0.3, 0.18, 0.42, 1.4, 3.2, rng.randf_range(0.46, 0.88), i))
	var grid := Steering.neighbor_grid(crowd)
	for mover: Dictionary in crowd:
		var comfort := float(mover.comfort)
		var alone := Steering._separate_velocity(mover, crowd, comfort)
		var shared := Steering._separate_velocity(mover, crowd, comfort, grid)
		assert_true(alone.distance_to(shared) < 0.00001, "separation differs: %s vs %s" % [alone, shared])


## How far a planted foot drifts over the ground during its stance, against how far the body
## moves meanwhile (0: it stays put). A foot is planted while it moves backward against the body
## in the lower half of its lift, as VillagerClips measures it.
func _slide(looks: Dictionary, speed: float) -> float:
	var figure := VillagerArt.make(looks, 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(figure)
	var animator := VillagerArt.animator(figure)
	animator.measure = false
	animator.set_process(false)
	VillagerArt.set_locomotion_speed(figure, speed)
	for i: int in 60:
		animator.update(DT)
	var skeleton := animator.skeleton
	var feet := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	var frames := 180
	var ground: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	var height: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	for frame: int in frames:
		animator.update(DT)
		for side: int in 2:
			var foot := VillagerArt._bone_global(skeleton, int(feet[side])).origin
			# The skeleton faces -Y and is Z-up. The body moves forward at speed.
			ground[side].append(speed * DT * frame - foot.y * animator.world_per_unit)
			height[side].append(foot.z)
	var drift := 0.0
	var travel := 0.0
	for side: int in 2:
		var low := 999.0
		var high := -999.0
		for h: float in height[side]:
			low = minf(low, h)
			high = maxf(high, h)
		var start := -1
		for frame: int in range(1, frames):
			var body_step := speed * DT
			var foot_back := ground[side][frame] - ground[side][frame - 1] < body_step
			var planted := foot_back and height[side][frame] <= low + (high - low) * VillagerClips.CONTACT_BAND
			if planted and start == -1:
				start = frame - 1
			elif not planted and start != -1:
				drift += absf(ground[side][frame - 1] - ground[side][start])
				travel += speed * DT * (frame - 1 - start)
				start = -1
	figure.free()
	return drift / maxf(travel, 0.0001)
