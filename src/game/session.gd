class_name Session
extends RefCounted
## The core loop for one era: the Oracle speaks a prophecy, the world plays out while the
## player intervenes, and when the prophecy comes true or breaks, the Chronicler explains why.
## When the island meets its destiny (see DestinySystem), the Chronicler writes its last chapter;
## the world keeps living afterwards.
## Holds no rendering, so the whole loop can be tested headless. When dilemma cards come is up
## to the DramaManager, which reads the world but never changes it.

signal phase_changed(phase: Phase)
## The chronicle's story so far, while the Chronicler writes it (CHRONICLING); last, its final text.
signal story_streamed(text: String)

enum Phase {
	FORETELLING, ## waiting for the Oracle's prophecy
	PLAYING, ## the prophecy is active and time runs
	CHRONICLING, ## the prophecy resolved; waiting for the chronicle
	REVEAL, ## showing the chronicle; time is stopped until the player continues
	DECIDING, ## showing a dilemma card; time is stopped until the player chooses
}

var sim: Simulation
var oracle: Oracle
var phase: Phase = Phase.FORETELLING
## The chronicle for the last resolved prophecy: {"title", "text", "causes"}, or the island's last
## chapter when it met its destiny (then it also has "destiny": the kind).
var chronicle: Dictionary = {}
## The story text written so far while CHRONICLING ("" until the first words arrive).
var story_so_far := ""
## True while CHRONICLING the island's last chapter rather than a prophecy's chronicle.
var writing_destiny := false
## The dilemma on screen while DECIDING.
var dilemma: Dilemma
## Paces the story: tension, its target and when the next card is due.
var drama := DramaManager.new()

var _fetching_dilemma := false
var _ready_dilemma: Dilemma


func _init(simulation: Simulation, ai_oracle: Oracle) -> void:
	sim = simulation
	oracle = ai_oracle


## Starts (or restarts) the loop by asking for a prophecy.
func begin() -> void:
	drama.begin(sim.state.tick, sim.state.next_event_id - 1)
	_set_phase(Phase.FORETELLING)
	var prophecy: Prophecy = await oracle.request_prophecy(sim.state, drama.pacing_hint())
	sim.state.prophecy = prophecy
	_set_phase(Phase.PLAYING)


## Time only moves while PLAYING. Returns how many ticks actually ran.
func advance(ticks: int) -> int:
	var ran := 0
	while ran < ticks and phase == Phase.PLAYING:
		sim.advance()
		ran += 1
		drama.observe(sim.state)
		if not sim.state.destiny.is_empty() and not sim.state.destiny.has("told"):
			_last_chapter()
		elif sim.state.prophecy == null and sim.state.resolved_prophecy != null:
			_chronicle()
		elif phase == Phase.PLAYING:
			_update_dilemma()
	return ran


## Shows a dilemma right away (debug and UI tests).
func present(card: Dilemma) -> void:
	if phase == Phase.PLAYING and card != null:
		_show_dilemma(card)


## Resolves the current prophecy as broken and shows the given chronicle (debug and UI tests).
func present_reveal(written: Dictionary) -> void:
	if not _break_prophecy():
		return
	chronicle = written
	drama.note_reveal()
	_set_phase(Phase.REVEAL)


## Resolves the current prophecy as broken and stays CHRONICLING with this much of the story
## written, as if it were still streaming in (debug and UI tests; nothing finishes it).
func present_chronicling(partial_text: String) -> void:
	if not _break_prophecy():
		return
	writing_destiny = false
	_set_phase(Phase.CHRONICLING)
	_on_story(partial_text)


func _break_prophecy() -> bool:
	var state := sim.state
	if phase != Phase.PLAYING or state.prophecy == null:
		return false
	state.prophecy.status = Prophecy.Status.BROKEN
	state.prophecy.resolved_tick = state.tick
	state.resolved_prophecy = state.prophecy
	state.prophecy = null
	return true


## Answers the dilemma on screen and lets time run again.
func choose(index: int) -> void:
	if phase != Phase.DECIDING:
		return
	dilemma.choose(sim.state, index)
	dilemma = null
	_set_phase(Phase.PLAYING)


func _update_dilemma() -> void:
	if _ready_dilemma != null:
		var card := _ready_dilemma
		_ready_dilemma = null
		if card.still_valid(sim.state):
			_show_dilemma(card)
		else:
			drama.postpone(WorldState.DAYS_PER_YEAR)
		return
	if not _fetching_dilemma and drama.is_due():
		_request_dilemma()


func _show_dilemma(card: Dilemma) -> void:
	dilemma = card
	drama.note_card()
	_set_phase(Phase.DECIDING)


## Runs in the background: time keeps moving while the AI writes. The card is checked
## against the world again before it is shown.
func _request_dilemma() -> void:
	_fetching_dilemma = true
	var card: Dilemma = await oracle.request_dilemma(sim.state, drama.pacing_hint())
	_fetching_dilemma = false
	if card == null:
		drama.postpone(WorldState.DAYS_PER_YEAR)
	_ready_dilemma = card


func cast_miracle(id: String, tribe_name: String = "") -> bool:
	return phase == Phase.PLAYING and Miracles.cast(sim.state, id, tribe_name)


## From the reveal, moves on to the next prophecy (or, after the last chapter, back to the
## prophecy that was running).
func continue_after_reveal() -> void:
	if phase != Phase.REVEAL:
		return
	var after_destiny := chronicle.has("destiny")
	chronicle = {}
	story_so_far = ""
	if after_destiny and sim.state.prophecy != null:
		_set_phase(Phase.PLAYING)
		return
	sim.state.resolved_prophecy = null
	await begin()


func _chronicle() -> void:
	drama.note_reveal()
	story_so_far = ""
	writing_destiny = false
	_set_phase(Phase.CHRONICLING)
	chronicle = await oracle.request_chronicle(sim.state, sim.state.resolved_prophecy, _on_story)
	_set_phase(Phase.REVEAL)


func _last_chapter() -> void:
	sim.state.destiny["told"] = 1
	drama.note_destiny()
	story_so_far = ""
	writing_destiny = true
	_set_phase(Phase.CHRONICLING)
	chronicle = await oracle.request_destiny(sim.state, _on_story)
	chronicle["destiny"] = String(sim.state.destiny["kind"])
	_set_phase(Phase.REVEAL)


func _on_story(text: String) -> void:
	story_so_far = text
	story_streamed.emit(text)


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_changed.emit(phase)
