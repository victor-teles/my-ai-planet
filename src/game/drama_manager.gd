class_name DramaManager
extends RefCounted
## Paces the story: decides when the next dilemma card is due. Reads the world's events but never
## writes to the world and draws no random numbers, so it can't change what the sim does on its own.
## Tension (0-100) rises with drama (deaths in war, famine, drought, war, splits, revolutions, the
## god's big moments) and fades in calm years. Each prophecy cycle has a target tension that
## builds toward the deadline and is released after the reveal. A card comes sooner when the
## story sits below its target, waits when it sits above, and a fresh dramatic event can bring
## one early. Hard cooldowns keep cards apart whatever the story does.

const MAX_TENSION := 100.0
const HALF_LIFE_YEARS := 1.5 ## a calm stretch this long halves the tension
## Tension each event type adds (negative: relief). Types missing here add nothing.
const WEIGHTS := {
	"famine": 12.0, "epidemic": 14.0, "drought_started": 10.0, "water_low": 6.0, "disaster": 16.0,
	"war": 22.0, "raid": 6.0, "incident": 4.0, "fight": 1.0, "vassal": 8.0, "vassal_revolt": 12.0,
	"tribe_split": 14.0, "tribe_extinct": 18.0, "tribes_merged": 6.0, "tribe_moved": 4.0, "annexed": 10.0,
	"revolution": 25.0, "coup": 20.0, "uprising_crushed": 12.0, "crackdown": 8.0, "protests": 6.0,
	"succession_war": 18.0, "succession_split": 12.0, "succession_contested": 6.0, "schism": 10.0,
	"capture": 10.0, "new_dynasty": 6.0, "prophet": 5.0, "arrest": 2.0, "exiled": 3.0, "bondage": 6.0,
	"miracle": 3.0, "dilemma": 6.0, "prophecy_fulfilled": 10.0, "prophecy_broken": 10.0, "destiny": 30.0,
	"drought_ended": -5.0, "protests_faded": -3.0, "succession_settled": -4.0, "gifts": -2.0,
}
const DEATH_WEIGHT := 0.4 ## a death of old age, illness or accident
const MAJOR_DEATH_WEIGHT := 2.0 ## a chief, or a death in war, plague or uprising

## Target tension across a prophecy cycle: REST at its start, PEAK at its deadline; CALM right
## after a reveal, easing back to REST over RELEASE_YEARS.
const CALM_TARGET := 5.0
const REST_TARGET := 10.0
const PEAK_TARGET := 50.0
const RELEASE_YEARS := 3.0

## Scheduled cards: SHORTEST_GAP_YEARS when the story sits far below its target, LONGEST when far above.
const SHORTEST_GAP_YEARS := 5.0
const LONGEST_GAP_YEARS := 11.0
const NEED_SPREAD := 40.0 ## tension below or above target that moves the gap all the way
## A fresh event at least this dramatic can bring a card early (not for the god's own deeds),
## unless the story is already this far above its target.
const HOOK_WEIGHT := 10.0
const HOOK_MIN_GAP_YEARS := 3.0
const HOOK_FRESH_YEARS := 1.0
const HOOK_CALM_MARGIN := 25.0
## Hard limits, whatever the story does.
const MIN_GAP_YEARS := 2.5
const REVEAL_QUIET_YEARS := 2.0
const DESTINY_QUIET_YEARS := 3.0
const WINDOW_YEARS := 15.0
const MAX_CARDS_PER_WINDOW := 3
const CATEGORY_COOLDOWN_YEARS := 8.0 ## the same kind of drama brings a card early at most this often
const YEAR_DAYS := float(WorldState.DAYS_PER_YEAR)

var _started := false
var _world_id := 0 ## the WorldState being watched; another one means a save was loaded
var _tick := 0
var _tension := 0.0
var _last_seen_event_id := -1
var _last_card_tick := 0
var _card_ticks: Array[int] = [] ## the newest cards, at most MAX_CARDS_PER_WINDOW
var _quiet_until := 0
var _release_tick := -1
var _cycle_start := 0
var _cycle_end := 0 ## no cycle while equal to _cycle_start
var _hook_category := ""
var _hook_tick := -1
var _heaviest := 0.0 ## the most dramatic event since the last card, and its category
var _heaviest_category := ""
var _category_cards: Dictionary = {} ## category -> tick it last brought a card


## Starts pacing at this tick; events up to last_event_id are already history. Idempotent.
func begin(tick: int, last_event_id: int) -> void:
	if _started:
		return
	_started = true
	_restart(tick, last_event_id)


## Call after every sim tick: fades tension, follows the prophecy cycle and feels new events.
func observe(state: WorldState) -> void:
	if state.get_instance_id() != _world_id:
		if _world_id != 0:
			_restart(state.tick, state.next_event_id - 1) # a save was loaded
		_world_id = state.get_instance_id()
	advance_to(state.tick)
	if state.prophecy != null:
		var deadline := state.prophecy.deadline_year * WorldState.DAYS_PER_YEAR
		set_cycle(state.prophecy.start_tick, deadline)
	var first := state.events.size()
	while first > 0 and int(state.events[first - 1]["id"]) > _last_seen_event_id:
		first -= 1
	for j: int in range(first, state.events.size()):
		feel(state.events[j])
	_last_seen_event_id = state.next_event_id - 1


## Lets time pass: tension halves every HALF_LIFE_YEARS.
func advance_to(tick: int) -> void:
	if tick > _tick:
		_tension *= pow(0.5, float(tick - _tick) / (HALF_LIFE_YEARS * YEAR_DAYS))
	_tick = tick


## The prophecy cycle the target builds across.
func set_cycle(start_tick: int, deadline_tick: int) -> void:
	_cycle_start = start_tick
	_cycle_end = maxi(deadline_tick, start_tick)


## One event's drama. Tension saturates toward MAX_TENSION; relief can bring it down.
func feel(event: Dictionary) -> void:
	var weight := weight_of(event)
	if weight > 0.0:
		_tension += weight * (1.0 - _tension / MAX_TENSION)
	else:
		_tension = maxf(_tension + weight, 0.0)
	var category := EventText.category(event)
	if weight <= 0.0 or category == "god":
		return
	if weight > _heaviest:
		_heaviest = weight
		_heaviest_category = category
	if weight >= HOOK_WEIGHT and not _cooling(category):
		_hook_category = category
		_hook_tick = _tick


static func weight_of(event: Dictionary) -> float:
	if String(event["type"]) == "death":
		return MAJOR_DEATH_WEIGHT if EventText.is_major(event) else DEATH_WEIGHT
	return float(WEIGHTS.get(String(event["type"]), 0.0))


## A card went on screen.
func note_card() -> void:
	_last_card_tick = _tick
	_card_ticks.append(_tick)
	if _card_ticks.size() > MAX_CARDS_PER_WINDOW:
		_card_ticks.remove_at(0)
	var category := _hook_category if _hook_fresh() else _heaviest_category
	if category:
		_category_cards[category] = _tick
	_hook_category = ""
	_heaviest = 0.0
	_heaviest_category = ""


## A prophecy was revealed: release the tension curve and keep cards away for a while.
func note_reveal() -> void:
	_release(REVEAL_QUIET_YEARS)


## The island met its destiny and its last chapter was told.
func note_destiny() -> void:
	_release(DESTINY_QUIET_YEARS)


## No card for a while (the last one fell through).
func postpone(days: int) -> void:
	_quiet_until = maxi(_quiet_until, _tick + days)


func tension() -> float:
	return _tension


## Where the tension should be now, on this prophecy cycle's curve.
func target() -> float:
	var progress := 0.0
	if _cycle_end > _cycle_start:
		progress = clampf(float(_tick - _cycle_start) / float(_cycle_end - _cycle_start), 0.0, 1.0)
	var rest := REST_TARGET
	if _release_tick >= 0:
		rest = lerpf(CALM_TARGET, REST_TARGET, clampf((_tick - _release_tick) / (RELEASE_YEARS * YEAR_DAYS), 0.0, 1.0))
	return rest + (PEAK_TARGET - REST_TARGET) * progress * progress


## Days until a card is due, as things stand (drama can still bring it sooner or push it back).
func days_until_next() -> int:
	var due := maxi(_quiet_until, _last_card_tick + roundi(MIN_GAP_YEARS * YEAR_DAYS))
	if _card_ticks.size() >= MAX_CARDS_PER_WINDOW:
		due = maxi(due, _card_ticks[0] + roundi(WINDOW_YEARS * YEAR_DAYS))
	if _hook_fresh() and _tension <= target() + HOOK_CALM_MARGIN:
		due = maxi(due, _last_card_tick + roundi(HOOK_MIN_GAP_YEARS * YEAR_DAYS))
	else:
		due = maxi(due, _last_card_tick + roundi(gap_years() * YEAR_DAYS))
	return maxi(due - _tick, 0)


func is_due() -> bool:
	return _started and days_until_next() == 0


## How long the story wants between scheduled cards right now.
func gap_years() -> float:
	var need := clampf(0.5 + (target() - _tension) / NEED_SPREAD, 0.0, 1.0)
	return lerpf(LONGEST_GAP_YEARS, SHORTEST_GAP_YEARS, need)


## A few words on what the story needs now, for the Oracle's prompts.
func pacing_hint() -> String:
	if _release_tick >= 0 and _tick - _release_tick < RELEASE_YEARS * YEAR_DAYS:
		return "the story just peaked; let it breathe"
	var gap := _tension - target()
	if gap > 15.0:
		return "the story needs calm"
	if gap < -15.0:
		return "raise the stakes"
	if _cycle_end > _cycle_start and _tick - _cycle_start > 0.75 * (_cycle_end - _cycle_start):
		return "build toward the deadline"
	return "keep the story moving"


func _release(quiet_years: float) -> void:
	_release_tick = _tick
	_quiet_until = maxi(_quiet_until, _tick + roundi(quiet_years * YEAR_DAYS))
	_hook_category = ""


func _restart(tick: int, last_event_id: int) -> void:
	_tick = tick
	_last_seen_event_id = last_event_id
	_last_card_tick = tick
	_card_ticks.clear()
	_quiet_until = 0
	_release_tick = -1
	_hook_category = ""
	_category_cards.clear()


func _hook_fresh() -> bool:
	return _hook_category != "" and _tick - _hook_tick <= HOOK_FRESH_YEARS * YEAR_DAYS


func _cooling(category: String) -> bool:
	return _category_cards.has(category) and _tick - int(_category_cards[category]) < CATEGORY_COOLDOWN_YEARS * YEAR_DAYS
