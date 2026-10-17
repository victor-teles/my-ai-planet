class_name SimSystem
extends RefCounted
## Base class for simulation systems. Systems hold no state of their own:
## everything lives in WorldState so saving, loading and replaying stay exact.


func get_id() -> String:
	return "system"


## The system runs on ticks where tick % interval == 0.
func get_interval() -> int:
	return 1


func update(_state: WorldState) -> void:
	pass
