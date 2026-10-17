class_name Simulation
extends RefCounted
## Owns a WorldState and the systems that advance it. Has no rendering, so it runs headless in tests.

var state: WorldState
var scheduler: TickScheduler


func _init(world: WorldState) -> void:
	state = world
	scheduler = default_scheduler()


static func create(seed_value: int) -> Simulation:
	return Simulation.new(WorldState.create(seed_value))


static func default_scheduler() -> TickScheduler:
	var scheduler := TickScheduler.new()
	scheduler.add_system(ClimateSystem.new())
	scheduler.add_system(PopulationSystem.new())
	scheduler.add_system(InfluenceSystem.new())
	scheduler.add_system(ProphecySystem.new())
	return scheduler


func advance(ticks: int = 1) -> void:
	for i: int in ticks:
		scheduler.step(state)


func save_to(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(state.to_json())
	return OK


## Returns null if the file is missing or not a valid save.
static func load_from(path: String) -> Simulation:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return null
	var world := WorldState.from_dict(data)
	return Simulation.new(world) if world != null else null
