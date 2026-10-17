class_name ProphecySystem
extends SimSystem
## Checks the current prophecy once a year. Whether it comes true or breaks, the drama
## is rewarded with Influence and the prophecy moves to resolved_prophecy for the reveal.

const RESOLUTION_REWARD := 3.0


func get_id() -> String:
	return "prophecy"


func get_interval() -> int:
	return WorldState.MONTHS_PER_YEAR


func update(state: WorldState) -> void:
	if state.prophecy == null:
		return
	var status := state.prophecy.check(state)
	if status == Prophecy.Status.PENDING:
		return
	state.log_event("prophecy_fulfilled" if status == Prophecy.Status.FULFILLED else "prophecy_broken")
	state.influence = minf(state.influence + RESOLUTION_REWARD, WorldState.MAX_INFLUENCE)
	state.resolved_prophecy = state.prophecy
	state.prophecy = null
