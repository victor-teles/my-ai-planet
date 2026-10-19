class_name Prophecy
extends RefCounted
## A prediction the sim can check. The AI proposes it; from_proposal() decides whether it's allowed.

enum Status { PENDING, FULFILLED, BROKEN }

const METRICS: Array[String] = [
	"total_population", "tribe_count", "largest_tribe_population", "building_count", "discoveries",
	"highest_age", "max_dystopia", "max_inequality", "vassal_count",
]
const OPERATORS: Array[String] = [">=", "<="]
const MIN_YEARS := 5
const MAX_YEARS := 100

var text: String = ""
var metric: String = ""
var op: String = ""
var target: int = 0
var deadline_year: int = 0
var status: Status = Status.PENDING
var start_tick: int = 0
var resolved_tick: int = -1


## Turns an AI proposal into a prophecy, or returns null if it breaks the rules.
## Out-of-range numbers are clamped rather than rejected.
static func from_proposal(proposal: Dictionary, state: WorldState) -> Prophecy:
	var proposed_metric := String(proposal.get("metric", ""))
	var proposed_op := String(proposal.get("op", ""))
	var proposed_text := String(proposal.get("text", "")).strip_edges()
	if proposed_metric not in METRICS or proposed_op not in OPERATORS or proposed_text.is_empty():
		return null
	var prophecy := Prophecy.new()
	prophecy.text = proposed_text
	prophecy.metric = proposed_metric
	prophecy.op = proposed_op
	prophecy.target = maxi(int(proposal.get("value", 0)), 0)
	prophecy.start_tick = state.tick
	prophecy.deadline_year = state.year() + clampi(int(proposal.get("years_from_now", MIN_YEARS)), MIN_YEARS, MAX_YEARS)
	# A prophecy that is already true right now isn't a prediction.
	if prophecy._condition_met(state):
		return null
	return prophecy


## Call once per sim month. A prophecy comes true the first time its condition holds before the deadline.
func check(state: WorldState) -> Status:
	if status != Status.PENDING:
		return status
	if _condition_met(state):
		status = Status.FULFILLED
	elif state.year() >= deadline_year:
		status = Status.BROKEN
	if status != Status.PENDING:
		resolved_tick = state.tick
	return status


func to_dict() -> Dictionary:
	return {
		"text": text, "metric": metric, "op": op, "target": target, "deadline_year": deadline_year,
		"status": Status.keys()[status], "start_tick": start_tick, "resolved_tick": resolved_tick,
	}


static func from_dict(data: Dictionary) -> Prophecy:
	var prophecy := Prophecy.new()
	prophecy.text = String(data["text"])
	prophecy.metric = String(data["metric"])
	prophecy.op = String(data["op"])
	prophecy.target = int(data["target"])
	prophecy.deadline_year = int(data["deadline_year"])
	prophecy.status = Status.keys().find(String(data["status"])) as Status
	prophecy.start_tick = int(data["start_tick"])
	prophecy.resolved_tick = int(data["resolved_tick"])
	return prophecy


func _condition_met(state: WorldState) -> bool:
	var value := measure(metric, state)
	return value >= target if op == ">=" else value <= target


static func measure(metric_name: String, state: WorldState) -> int:
	match metric_name:
		"total_population":
			return state.total_population()
		"tribe_count":
			return state.tribe_count()
		"largest_tribe_population":
			var largest := 0
			for population: int in state.tribe_population:
				largest = maxi(largest, population)
			return largest
		"building_count":
			var built := 0
			for b: int in state.building_ids.size():
				if state.is_built(b) and state.building_types[b] != "fire":
					built += 1
			return built
		"discoveries":
			var known := {}
			for techs: PackedStringArray in state.tribe_knowledge:
				for tech: String in techs:
					if tech not in Knowledge.STARTING:
						known[tech] = true
			return known.size()
		"highest_age":
			var highest := 0
			for t: int in state.tribe_count():
				highest = maxi(highest, state.age_of(t))
			return highest
		"max_dystopia":
			var darkest := 0
			for t: int in state.tribe_count():
				darkest = maxi(darkest, Society.dystopia(state, t))
			return darkest
		"max_inequality":
			var widest := 0
			for t: int in state.tribe_count():
				widest = maxi(widest, Society.inequality(state, t))
			return widest
		"vassal_count":
			var vassals := 0
			for overlord: String in state.tribe_overlord:
				if overlord:
					vassals += 1
			return vassals
	push_error("Unknown prophecy metric: %s" % metric_name)
	return 0
