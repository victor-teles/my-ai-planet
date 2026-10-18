class_name EventPacer
extends RefCounted
## Keeps bursts of events from flooding the screen (the life feed and the diorama's pop-ups).
## Small events wait a moment so a burst can merge into one line ("3 children were born to the
## Kolu"); a budget of lines per second of real time drops small ones when too much happens at
## once. The big turns of history always get through at once, but they use up the budget too.

const GATHER_SECONDS := 0.6 ## small events wait this long so a burst can merge
## Event types that merge when several land in the same tribe: [line, short pop-up].
const MERGED := {
	"birth": ["{n} children were born to the {tribe}.", "{n} born"],
	"death": ["{n} of the {tribe} died.", "{n} died"],
	"marriage": ["{n} couples of the {tribe} married.", "{n} weddings"],
	"romance": ["{n} couples of the {tribe} fell in love.", "{n} in love"],
	"proposal_refused": ["{n} proposals among the {tribe} were refused.", "{n} said no"],
	"separation": ["{n} couples of the {tribe} parted.", "{n} parted"],
	"coming_of_age": ["{n} of the {tribe} came of age.", "{n} came of age"],
	"job": ["{n} of the {tribe} took up new work.", "{n} new trades"],
	"apprentice": ["{n} of the {tribe} became apprentices.", "{n} apprentices"],
	"adoption": ["{n} orphans of the {tribe} found a home.", "{n} adopted"],
	"fight": ["{n} fights broke out among the {tribe}.", "{n} fights"],
	"building_planned": ["The {tribe} planned {n} buildings.", "{n} planned"],
	"building_started": ["The {tribe} began {n} buildings.", "{n} begun"],
	"building_done": ["The {tribe} finished {n} buildings.", "{n} new buildings"],
	"tech_spread": ["The {tribe} learned {n} new crafts.", "{n} learned"],
}

var lines_per_second: float
var max_burst: float
var _budget: float
var _now: Array[Dictionary] = [] ## big news, shown on the next take()
var _waiting: Array[Dictionary] = [] ## small events gathering, oldest first
var _waited := 0.0


func _init(per_second: float, burst: float) -> void:
	lines_per_second = per_second
	max_burst = burst
	_budget = burst


## Queues a new event; push them oldest first.
func push(event: Dictionary) -> void:
	if EventText.is_major(event):
		_now.append(event)
	else:
		_waiting.append(event)


## Forgets everything queued (the view was rebuilt or a save was loaded).
func clear() -> void:
	_now.clear()
	_waiting.clear()
	_waited = 0.0


## Call every frame. Returns what to show now, oldest first, as items: {"event": the newest
## event of a group, "count": how many merged into it, "major": whether any of them was major}.
func take(delta: float) -> Array[Dictionary]:
	_budget = minf(_budget + delta * lines_per_second, max_burst)
	var shown := group(_now)
	_now.clear()
	_budget = maxf(_budget - shown.size(), -max_burst)
	if _waiting.is_empty():
		_waited = 0.0
	else:
		_waited += delta
	if _waited >= GATHER_SECONDS:
		var small := group(_waiting)
		# The biggest bursts say the most in one line: they go first while the budget lasts.
		small.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"]))
		for item: Dictionary in small:
			if _budget >= 1.0:
				_budget -= 1.0
				shown.append(item)
		clear()
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["event"]["id"]) < int(b["event"]["id"]))
	return shown


## Merges events of a MERGED type in the same tribe. Chiefs' deaths stay on their own.
static func group(events: Array[Dictionary]) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var by_key := {}
	for event: Dictionary in events:
		var key := _key(event)
		if key and by_key.has(key):
			var item: Dictionary = by_key[key]
			item["event"] = event
			item["count"] = int(item["count"]) + 1
			item["major"] = bool(item["major"]) or EventText.is_major(event)
			continue
		var fresh := {"event": event, "count": 1, "major": EventText.is_major(event)}
		items.append(fresh)
		if key:
			by_key[key] = fresh
	return items


## The merged words for an item of more than one event: a feed line, or a short pop-up.
static func burst_text(item: Dictionary, short: bool = false) -> String:
	var event: Dictionary = item["event"]
	var words: Array = MERGED[String(event["type"])]
	return String(words[1 if short else 0]).format({"n": int(item["count"]), "tribe": EventText.tribe_of(event)})


static func _key(event: Dictionary) -> String:
	var type := String(event["type"])
	var tribe := EventText.tribe_of(event)
	if not MERGED.has(type) or tribe.is_empty():
		return ""
	if type == "death" and int((event["data"] as Dictionary).get("chief", 0)) == 1:
		return ""
	return "%s|%s" % [type, tribe]
