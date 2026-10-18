class_name AssetDirector
extends RefCounted
## Asks the AI for asset specs (see AssetKind) while the player plays: when a tribe is founded,
## enters a new age, changes government or meets its destiny, a kind's signature for it changes
## and a new spec is written. One small call each, one at a time, in the background; the
## specs go into the world (AssetBook), so a reload or an unplugged AI looks the same.
## Asset calls may spend at most SHARE of the session's budget (money and calls); past that,
## and whenever a call fails, the kind's offline writer answers, so nothing waits on the AI.

## A spec was stored (new or replaced): views rebuild what shows it.
signal spec_changed(kind: String, subject: String)

const SHARE := 0.1 ## asset calls' share of the session's AI budget

var oracle: Oracle
var kinds: Array[AssetKind] = AssetKinds.all()
## Specs written so far this session: {"ai": n, "offline": n}.
var written := {"ai": 0, "offline": 0}

var _state: WorldState
var _queue: Array[Array] = [] ## [kind, subject], best priority first
var _queued := {} ## AssetBook key -> true
var _busy := false
var _checked_tick := -1


func _init(ai_oracle: Oracle) -> void:
	oracle = ai_oracle


## Call every tick (cheap): once a month, and right away for a new world, queues every spec
## that is missing or stale and starts writing them in the background.
func observe(state: WorldState) -> void:
	if state != _state:
		_state = state
		_queue.clear()
		_queued.clear()
		_checked_tick = -1
	if _checked_tick != -1 and (state.tick == _checked_tick or not state.is_month_start()):
		return
	_checked_tick = state.tick
	for kind: AssetKind in kinds:
		for subject: String in kind.subjects(state):
			var key := AssetBook.key(kind.task(), subject)
			if _queued.has(key) or not _is_stale(state, kind, subject):
				continue
			_queued[key] = true
			_queue.append([kind, subject])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as AssetKind).priority() < (b[0] as AssetKind).priority())
	if not _busy and not _queue.is_empty():
		_drain(state)


## Writes every missing or stale spec now and waits for them (a new world before it is shown,
## and tests).
func settle(state: WorldState) -> void:
	observe(state)
	while _busy:
		await spec_changed


## True while specs are being written.
func is_busy() -> bool:
	return _busy


## The stored spec, or the kind's offline spec for the subject as it is now (not stored), so a
## view never waits for the AI.
static func spec_or_offline(state: WorldState, task: String, subject: String) -> Dictionary:
	var stored := AssetBook.spec(state, task, subject)
	if not stored.is_empty():
		return stored
	var kind := AssetKinds.find(task)
	return kind.offline_spec(state, subject) if kind else {}


## How much of the asset share is used, 0 to 1.
func used_share() -> float:
	return oracle.budget.share_of(AssetKinds.tasks()) / SHARE


func _is_stale(state: WorldState, kind: AssetKind, subject: String) -> bool:
	var wanted := kind.signature(state, subject)
	return not wanted.is_empty() and wanted != AssetBook.signature(state, kind.task(), subject)


func _drain(state: WorldState) -> void:
	_busy = true
	while not _queue.is_empty() and state == _state:
		var job: Array = _queue.pop_front()
		var kind: AssetKind = job[0]
		var subject: String = job[1]
		if _is_stale(state, kind, subject):
			await _write(state, kind, subject)
		_queued.erase(AssetBook.key(kind.task(), subject))
	_busy = false
	spec_changed.emit("", "")


func _write(state: WorldState, kind: AssetKind, subject: String) -> void:
	var signature := kind.signature(state, subject)
	var spec := {}
	var source := "offline"
	if used_share() < 1.0 and not oracle.offline_for(kind.task()):
		oracle.answered_by = ""
		spec = await oracle.request_asset(kind, state, subject)
		source = oracle.answered_by if oracle.answered_by else "offline"
	if state != _state or kind.signature(state, subject) != signature:
		return # the world moved on (or was replaced) while the AI wrote: the next check asks again
	if spec.is_empty():
		spec = kind.offline_spec(state, subject)
		source = "offline"
	if spec.is_empty():
		push_warning("AssetDirector: no %s for %s, not even offline" % [kind.task(), subject])
		return
	AssetBook.put(state, kind.task(), subject, spec, signature, source)
	kind.apply(state, subject, spec)
	written["offline" if source == "offline" else "ai"] += 1
	spec_changed.emit(kind.task(), subject)
