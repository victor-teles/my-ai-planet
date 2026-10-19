extends SceneTree
## Frame time with a full island of animals beside the villagers. The tool's own copy of the
## world is topped up to --animals (default 300) with copies of its herds, then the diorama runs
## with vsync off, the sim ticking at the game's 3x speed.
## Usage: godot --path src --resolution 1600x900 -s res://tools/animal_bench.gd -- [--seed=1]
##   [--years=30] [--animals=300] [--distance=30] [--frames=600]

var _options := {"seed": "1", "years": "30", "animals": "300", "distance": "30", "frames": "600"}
var _sim: Simulation
var _diorama: Diorama
var _frame := 0
var _measured := 0
var _start := 0
var _herd_usec := 0
var _worst := 0
var _last := 0
var _budget := 0.0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() == 2:
			_options[pair[0]] = pair[1]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var seed_value := int(_options["seed"])
	_sim = Simulation.create(seed_value)
	_sim.advance(int(_options["years"]) * WorldState.DAYS_PER_YEAR)
	var state := _sim.state
	var wanted := int(_options["animals"])
	var base := state.animal_ids.size()
	var n := 0
	while wanted == 0 and not state.animal_ids.is_empty():
		state.remove_animal(0)
	while state.animal_ids.size() < wanted and base > 0:
		var i := n % base
		state.add_animal(state.animal_species[i], state.animal_sex[i], state.animal_born[i] - n, state.animal_genomes[i], 80)
		n += 1
	_diorama = Diorama.new()
	root.add_child(_diorama)
	_diorama.build(state.world, seed_value)
	_diorama.mark_events_seen(state)
	_diorama.camera_rig.distance = float(_options["distance"])
	print("bench: %d people, %d animals, camera at %s" % [state.person_ids.size(), state.animal_ids.size(), _options["distance"]])


func _process(delta: float) -> bool:
	_frame += 1
	_budget += delta * 6.0
	while _budget >= 1.0:
		_sim.advance(1)
		_budget -= 1.0
	var before := Time.get_ticks_usec()
	_diorama.sync(_sim.state, delta)
	var after := Time.get_ticks_usec()
	if _frame == 120:
		_start = after
		_last = after
	elif _frame > 120:
		_measured += 1
		_herd_usec += after - before
		_worst = maxi(_worst, after - _last)
		_last = after
	if _measured >= int(_options["frames"]):
		var seconds := float(after - _start) / 1000000.0
		print("bench: %.1f fps average, worst frame %.1f ms, diorama.sync %.2f ms a frame, %d animals drawn" % [
			_measured / seconds, _worst / 1000.0, _herd_usec / 1000.0 / _measured, _diorama.herds.count()])
		return true
	return false
