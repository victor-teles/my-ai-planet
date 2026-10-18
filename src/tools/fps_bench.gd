extends SceneTree
## Frames per second with a fixed crowd: the island of a seed, warmed up some years, with its
## camps filled by exactly N villagers (default 300) who walk out to work, work, carry home,
## rest, teach, mourn and play. Runs in a real window (headless does not render), vsync off.
## Usage:
##   godot --path src --resolution 1600x1000 -s res://tools/fps_bench.gd -- [--villagers=300]
##     [--seconds=20] [--settle=5] [--seed=42] [--years=30] [--yaw=0.6] [--pitch=-0.42] [--distance=30]
##     [--focus=camp]  (centre the camera on the first camp instead of the island's middle)
## Prints one line: FPS_BENCH villagers=... avg=... min=... p1_low=... frames=...
## avg is frames over seconds; min is the slowest whole second; p1_low is 1000 / the 99th
## percentile frame time in ms.

const JOBS: Array[String] = ["woodcutter", "forager", "farmer", "builder", "hunter", "fisher", "quarrier", "healer",
	"toolmaker", "smith", "miner", "guard", "scholar", "merchant", "potter", "shaman"]

var _options: Dictionary = {}
var _state: WorldState
var _diorama: Diorama
var _people: Dictionary = {} ## tribe -> {id -> info}
var _elapsed := 0.0
var _measuring := false
var _frame_times: PackedFloat32Array = []
var _second_frames := 0
var _second_time := 0.0
var _seconds: PackedFloat32Array = []
var _last_usec := 0
var _process_ms := 0.0 ## summed over the measured frames: scripts and animation (idle step)
var _render_cpu_ms := 0.0
var _render_gpu_ms := 0.0
var _camps_ms := 0.0
var _camps_ms_now := 0.0
var _sync_ms := 0.0
var _sync_ms_now := 0.0
var _stopped := false ## --probe=nosettle


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		_options[pair[0]] = pair[1] if pair.size() > 1 else ""
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


## The root is not in the tree yet during _initialize, so the island is built on the first frame.
func _build() -> void:
	var seed_value := int(_options.get("seed", 42))
	var sim := Simulation.create(seed_value)
	sim.advance(int(_options.get("years", 30)) * WorldState.DAYS_PER_YEAR)
	_state = sim.state
	_diorama = Diorama.new()
	root.add_child(_diorama)
	_diorama.build(_state.world, seed_value)
	_diorama.mark_events_seen(_state)
	_diorama.sync(_state, 0.0)
	_crowd(int(_options.get("villagers", 300)), seed_value)
	var rig := _diorama.camera_rig
	rig.yaw = float(_options.get("yaw", rig.yaw))
	rig.pitch = float(_options.get("pitch", rig.pitch))
	rig.distance = float(_options.get("distance", rig.distance))
	if _options.has("focus"):
		var camp: Variant = _diorama.camp_position(_state.tribe_names[0])
		if camp != null:
			rig.focus = camp
			rig.position = camp
	_last_usec = Time.get_ticks_usec()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


## Splits the crowd over the camps, each person modeled on a real one (their genome) with a
## spread of ages and activities. Ids are far above the simulation's, so nobody collides.
func _crowd(count: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tribes := _state.tribe_names
	for tribe: String in tribes:
		_people[tribe] = {}
	var homes: Dictionary = {} ## tribe -> building ids of homes
	for b: int in _state.building_ids.size():
		if Buildings.is_home(_state.building_types[b]) and _state.is_built(b):
			var owner := _state.building_tribes[b]
			if not homes.has(owner):
				homes[owner] = []
			(homes[owner] as Array).append(_state.building_ids[b])
	for i: int in count:
		var tribe := tribes[i % tribes.size()]
		var model := rng.randi_range(0, _state.person_ids.size() - 1)
		var roll := rng.randf()
		var age := rng.randi_range(18, 54)
		var activity := "working"
		if roll < 0.14:
			age = rng.randi_range(4, 13)
			activity = "playing"
		elif roll < 0.22:
			age = rng.randi_range(60, 80)
			activity = "teaching" if rng.randf() < 0.4 else "idle"
		elif roll < 0.34:
			activity = "idle"
		elif roll < 0.39:
			activity = "resting"
		elif roll < 0.42:
			activity = "mourning"
		var tribe_homes: Array = homes.get(tribe, [])
		(_people[tribe] as Dictionary)[2_000_000 + i] = {
			"female": rng.randf() < 0.5, "age": age, "chief": false,
			"genome": _state.person_genomes[model], "activity": activity,
			"job": JOBS[rng.randi_range(0, JOBS.size() - 1)] if activity == "working" else "",
			"home": int(tribe_homes[rng.randi_range(0, tribe_homes.size() - 1)]) if not tribe_homes.is_empty() else -1,
			"mother": -1, "newborn": false,
		}


func _process(delta: float) -> bool:
	if _diorama == null:
		_build()
		return false
	# Keep the camps in step every frame, as the game does. The bench runs the camps' frame itself
	# so it can time the behavior (steering, planning, clip requests) apart from the rest.
	var started := Time.get_ticks_usec()
	_sync_ms_now = 0.0
	_camps_ms_now = 0.0
	for tribe: String in _people:
		var camp := _camp(tribe)
		if camp:
			camp.sync(_state, _people[tribe], {})
			_sync_ms_now += (Time.get_ticks_usec() - started) / 1000.0
			started = Time.get_ticks_usec()
			if camp.is_processing():
				camp.set_process(false)
			if not _stopped:
				camp._process(delta)
			_camps_ms_now += (Time.get_ticks_usec() - started) / 1000.0
			started = Time.get_ticks_usec()
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_elapsed += delta
	var settle := float(_options.get("settle", 5.0))
	var seconds := float(_options.get("seconds", 20.0))
	if _elapsed < settle:
		return false
	if not _measuring:
		_measuring = true
		_probe(String(_options.get("probe", "")))
		_second_time = 0.0
		_second_frames = 0
		return false
	_frame_times.append(frame_ms)
	_camps_ms += _camps_ms_now
	_sync_ms += _sync_ms_now
	_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var viewport := root.get_viewport_rid()
	_render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu()
	_render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	_second_frames += 1
	_second_time += frame_ms / 1000.0
	if _second_time >= 1.0:
		_seconds.append(_second_frames / _second_time)
		_second_time = 0.0
		_second_frames = 0
	if _elapsed < settle + seconds:
		return false
	_report()
	return true


## Turns one part off to see what it costs: "noanim" stops every villager's animation, "nosettle"
## stops the camps' per-frame behavior (steering, planning) but keeps the animation running.
func _probe(what: String) -> void:
	for tribe: String in _people:
		var camp := _camp(tribe)
		if camp == null:
			continue
		if what == "nosettle":
			_stopped = true
		if what == "noanim":
			for animator: Node in camp.find_children("Animator", "", true, false):
				animator.set_process(false)


func _camp(tribe: String) -> Settlement:
	for child: Node in _diorama.get_children():
		var camp := child as Settlement
		if camp and camp.tribe_name == tribe:
			return camp
	return null


func _report() -> void:
	var total := 0.0
	for ms: float in _frame_times:
		total += ms
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var p99: float = sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)]
	var slowest := 9999.0
	for fps: float in _seconds:
		slowest = minf(slowest, fps)
	var shown := 0
	for tribe: String in _people:
		var camp := _camp(tribe)
		if camp:
			shown += camp.person_ids().size()
	var frames := float(_frame_times.size())
	print("FPS_BENCH villagers=%d shown=%d avg=%.1f min=%.1f p1_low=%.1f frames=%d seconds=%.1f size=%s" % [
		int(_options.get("villagers", 300)), shown, frames / (total / 1000.0), slowest, 1000.0 / p99,
		_frame_times.size(), total / 1000.0, str(root.size)])
	print("FPS_BENCH_MS frame=%.2f sync=%.2f camps=%.2f process=%.2f render_cpu=%.2f render_gpu=%.2f" % [
		total / frames, _sync_ms / frames, _camps_ms / frames, _process_ms / frames, _render_cpu_ms / frames, _render_gpu_ms / frames])
