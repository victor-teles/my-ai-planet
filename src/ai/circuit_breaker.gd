class_name CircuitBreaker
extends RefCounted
## Stops asking a provider that keeps failing: after `threshold` failures in a row it is skipped for
## `cooldown_sec` real seconds, then gets one more chance (a failure then skips it again at once).
## Any success closes it.

var threshold := 3
var cooldown_sec := 60.0
## Returns seconds as a float from any fixed point. Tests swap in a fake clock.
var clock: Callable
var _failures := {} ## provider id -> failures in a row
var _open_until := {} ## provider id -> clock time it may be asked again


func _init() -> void:
	clock = func() -> float: return Time.get_ticks_msec() / 1000.0


func allows(provider_id: String) -> bool:
	return seconds_left(provider_id) <= 0.0


func is_open(provider_id: String) -> bool:
	return not allows(provider_id)


## Seconds until a skipped provider may be asked again, 0 if it may be now.
func seconds_left(provider_id: String) -> float:
	if not _open_until.has(provider_id):
		return 0.0
	return maxf(float(_open_until[provider_id]) - float(clock.call()), 0.0)


func failures(provider_id: String) -> int:
	return int(_failures.get(provider_id, 0))


func success(provider_id: String) -> void:
	_failures.erase(provider_id)
	_open_until.erase(provider_id)


func failure(provider_id: String) -> void:
	_failures[provider_id] = failures(provider_id) + 1
	if failures(provider_id) >= threshold:
		_open_until[provider_id] = float(clock.call()) + cooldown_sec
