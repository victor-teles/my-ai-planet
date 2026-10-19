class_name AIUsage
extends RefCounted
## The usage meter: calls, failures, cache hits, tokens, cost and latency, per provider and per task.
## It is the player's money, so the AI Settings screen shows this.

const FIELDS: Array[String] = ["calls", "failures", "cache_hits", "input_tokens", "output_tokens"]

var _by_provider := {} ## provider id -> totals
var _by_task := {} ## task -> totals


## A finished call (successful or not; a failed reply is also counted by failure()).
func record_call(provider_id: String, task: String, response: AIResponse) -> void:
	for totals: Dictionary in _totals(provider_id, task):
		totals["calls"] += 1
		totals["input_tokens"] += response.input_tokens
		totals["output_tokens"] += response.output_tokens
		totals["cost_usd"] += response.cost_usd
		totals["latency_ms"] += response.latency_ms


## A call that failed, or whose reply was rejected (schema, content ceiling or the sim's rules).
func record_failure(provider_id: String, task: String) -> void:
	for totals: Dictionary in _totals(provider_id, task):
		totals["failures"] += 1


## A question answered by the cache, or by sharing a call already in flight: free.
func record_hit(provider_id: String, task: String) -> void:
	for totals: Dictionary in _totals(provider_id, task):
		totals["cache_hits"] += 1


## {"providers": {id: stats}, "tasks": {task: stats}, "total": stats}, where stats is
## {"calls", "failures", "cache_hits", "input_tokens", "output_tokens", "cost_usd", "avg_latency_ms"}.
func report() -> Dictionary:
	var total := _empty()
	var providers := {}
	for id: String in _by_provider:
		providers[id] = _stats(_by_provider[id])
		for field: String in total:
			total[field] += _by_provider[id][field]
	var tasks := {}
	for task: String in _by_task:
		tasks[task] = _stats(_by_task[task])
	return {"providers": providers, "tasks": tasks, "total": _stats(total)}


func _totals(provider_id: String, task: String) -> Array[Dictionary]:
	if not _by_provider.has(provider_id):
		_by_provider[provider_id] = _empty()
	if not _by_task.has(task):
		_by_task[task] = _empty()
	return [_by_provider[provider_id], _by_task[task]]


func _empty() -> Dictionary:
	var totals := {"cost_usd": 0.0, "latency_ms": 0}
	for field: String in FIELDS:
		totals[field] = 0
	return totals


func _stats(totals: Dictionary) -> Dictionary:
	var stats := totals.duplicate()
	stats.erase("latency_ms")
	stats["avg_latency_ms"] = float(totals["latency_ms"]) / totals["calls"] if int(totals["calls"]) > 0 else 0.0
	return stats
