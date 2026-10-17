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
	DECIDING, ## showing a dilemma card; time is stopped until the player chooses
}

const DILEMMA_MIN_YEARS := 18
const DILEMMA_MAX_YEARS := 30
## Drama (famine, drought, a split) can bring the next dilemma early, but not sooner than this.
const DRAMA_MIN_YEARS := 12
const DRAMATIC_EVENTS: Array[String] = ["famine", "drought_started", "tribe_split"]

var sim: Simulation
var oracle: Oracle
var phase: Phase = Phase.FORETELLING
## The chronicle for the last resolved prophecy: {"title", "text", "causes"}.
var chronicle: Dictionary = {}
## The dilemma on screen while DECIDING.
var dilemma: Dilemma

var _next_dilemma_tick := -1
var _last_dilemma_tick := 0
var _last_seen_event_id := -1
var _fetching_dilemma := false
var _ready_dilemma: Dilemma


func _init(simulation: Simulation, ai_oracle: Oracle) -> void:
	sim = simulation
	oracle = ai_oracle


## Starts (or restarts) the loop by asking for a prophecy.
func begin() -> void:
	if _next_dilemma_tick < 0:
		_last_dilemma_tick = sim.state.tick
		_last_seen_event_id = sim.state.next_event_id - 1
		_schedule_dilemma()
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
		elif phase == Phase.PLAYING:
			_update_dilemma()
	return ran


## Answers the dilemma on screen and lets time run again.
func choose(index: int) -> void:
	if phase != Phase.DECIDING:
		return
	dilemma.choose(sim.state, index)
	dilemma = null
	_last_dilemma_tick = sim.state.tick
	_last_seen_event_id = sim.state.next_event_id - 1
	_schedule_dilemma()
	_set_phase(Phase.PLAYING)


func _update_dilemma() -> void:
	if _ready_dilemma != null:
		var card := _ready_dilemma
		_ready_dilemma = null
		if card.still_valid(sim.state):
			dilemma = card
			_set_phase(Phase.DECIDING)
		else:
			_next_dilemma_tick = sim.state.tick + WorldState.MONTHS_PER_YEAR
		return
	if _fetching_dilemma:
		return
	var dramatic := false
	for event: Dictionary in sim.state.events.slice(maxi(sim.state.events.size() - 5, 0)):
		if int(event["id"]) > _last_seen_event_id and String(event["type"]) in DRAMATIC_EVENTS:
			dramatic = true
	_last_seen_event_id = sim.state.next_event_id - 1
	var since_last := sim.state.tick - _last_dilemma_tick
	if sim.state.tick >= _next_dilemma_tick or (dramatic and since_last >= DRAMA_MIN_YEARS * WorldState.MONTHS_PER_YEAR):
		_request_dilemma()


## Runs in the background: time keeps moving while the AI writes. The card is checked
## against the world again before it is shown.
func _request_dilemma() -> void:
	_fetching_dilemma = true
	var card: Dilemma = await oracle.request_dilemma(sim.state)
	_fetching_dilemma = false
	if card == null:
		_schedule_dilemma()
	_ready_dilemma = card


func _schedule_dilemma() -> void:
	var years := DILEMMA_MIN_YEARS + posmod(hash([sim.state.seed_value, sim.state.tick]), DILEMMA_MAX_YEARS - DILEMMA_MIN_YEARS + 1)
	_next_dilemma_tick = sim.state.tick + years * WorldState.MONTHS_PER_YEAR


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
