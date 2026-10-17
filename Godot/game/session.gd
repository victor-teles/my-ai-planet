class_name Session
extends RefCounted
## The core loop for one era: the Oracle speaks a prophecy, the world plays out while the
## player intervenes, and when the prophecy comes true or breaks, the Chronicler explains why.
## Holds no rendering, so the whole loop can be tested headless.

signal phase_changed(phase: Phase)

enum Phase {
	FORETELLING, ## waiting for the Oracle's prophecy
	PLAYING, ## the prophecy is active and time runs
	CHRONICLING, ## the prophecy resolved; waiting for the chronicle
	REVEAL, ## showing the chronicle; time is stopped until the player continues
}

var sim: Simulation
var oracle: Oracle
var phase: Phase = Phase.FORETELLING
## The chronicle for the last resolved prophecy: {"title", "text", "causes"}.
var chronicle: Dictionary = {}


func _init(simulation: Simulation, ai_oracle: Oracle) -> void:
	sim = simulation
	oracle = ai_oracle


## Starts (or restarts) the loop by asking for a prophecy.
func begin() -> void:
	_set_phase(Phase.FORETELLING)
	var prophecy: Prophecy = await oracle.request_prophecy(sim.state)
	sim.state.prophecy = prophecy
	_set_phase(Phase.PLAYING)


## Time only moves while PLAYING. Returns how many ticks actually ran.
func advance(ticks: int) -> int:
	var ran := 0
	while ran < ticks and phase == Phase.PLAYING:
		sim.advance()
		ran += 1
		if sim.state.prophecy == null and sim.state.resolved_prophecy != null:
			_chronicle()
	return ran


func cast_miracle(id: String, tribe_name: String = "") -> bool:
	return phase == Phase.PLAYING and Miracles.cast(sim.state, id, tribe_name)


## From the reveal, moves on to the next prophecy.
func continue_after_reveal() -> void:
	if phase == Phase.REVEAL:
		sim.state.resolved_prophecy = null
		chronicle = {}
		await begin()


func _chronicle() -> void:
	_set_phase(Phase.CHRONICLING)
	chronicle = await oracle.request_chronicle(sim.state, sim.state.resolved_prophecy)
	_set_phase(Phase.REVEAL)


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_changed.emit(phase)
