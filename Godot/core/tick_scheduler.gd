class_name TickScheduler
extends RefCounted
## Runs systems in registration order. The order is part of the simulation's rules:
## changing it changes what a seed produces.

var _systems: Array[SimSystem] = []


func add_system(system: SimSystem) -> void:
	assert(system.get_interval() > 0, "System interval must be positive")
	_systems.append(system)


func step(state: WorldState) -> void:
	for system: SimSystem in _systems:
		if state.tick % system.get_interval() == 0:
			system.update(state)
	state.tick += 1
